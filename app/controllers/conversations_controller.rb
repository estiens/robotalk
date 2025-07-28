# frozen_string_literal: true

class ConversationsController < ApplicationController
  before_action :require_user
  def index
    @conversations = current_user.conversations
                                 .includes(:participants, :messages)
                                 .order(created_at: :desc)
  end

  def show
    @conversation = current_user.conversations
                                .includes(:participants)
                                .find(params[:id])
  end

  def new
    @conversation = current_user.conversations.build
    # Build two default participants
    # Build two default participants with a default model
    2.times do |_i|
      participant = @conversation.participants.build
      # Set default model for the participant
      participant.model_id = 'deepseek/deepseek-r1-0528'
    end
    @available_models = get_available_models
  end

  def edit
    @conversation = current_user.conversations.find(params[:id])
    @available_models = get_available_models
  end

  def create
    @conversation = current_user.conversations.build(conversation_params)

    if params[:generate_in_background]
      @conversation.status = :in_progress
      if @conversation.save
        GenerateConversationJob.perform_later(@conversation)
        redirect_to conversations_path, notice: 'Conversation is being generated in the background.'
      else
        handle_creation_failure
      end
    else
      @conversation.status = :pending
      if @conversation.save
        redirect_to @conversation, notice: 'Conversation created successfully! You can now start it.'
      else
        handle_creation_failure
      end
    end
  end

  def update
    @conversation = current_user.conversations.find(params[:id])

    if @conversation.update(conversation_params)
      redirect_to @conversation, notice: 'Conversation updated successfully!'
    else
      @available_models = get_available_models
      render :edit, status: :unprocessable_entity
    end
  end

  def debug
    @conversation = current_user.conversations
                                .includes(:participants, :messages)
                                .find(params[:id])
    render json: {
      conversation: {
        id: @conversation.id,
        topic: @conversation.conversation_topic,
        dialogue_instructions: @conversation.dialogue_instructions,
        max_rounds: @conversation.max_rounds,
        current_round: @conversation.current_round,
        can_continue: @conversation.ready_for_next_round?,
        message_count: @conversation.messages.count,
        participant_count: @conversation.participants.count
      },
      participants: @conversation.participants.map do |p|
        {
          id: p.id,
          name: p.name,
          model_id: p.model_id,
          turn_order: p.turn_order,
          system_prompt: p.system_prompt,
          character_prompt: p.character_prompt,
          full_system_prompt: p.system_prompt_with_topic
        }
      end,
      messages: @conversation.messages.map do |m|
        {
          id: m.id,
          role: m.role,
          model_id: m.model_id,
          content_length: m.content&.length || 0,
          created_at: m.created_at,
          metadata: m.metadata
        }
      end
    }
  end

  def start
    @conversation = current_user.conversations
                                .includes(:participants)
                                .find(params[:id])

    unless @conversation.can_start?
      alert_message = @conversation.pending? ? 'Conversation must have at least 2 participants to start.' : 'This conversation cannot be started.'
      respond_to do |format|
        format.html { redirect_to @conversation, alert: alert_message }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace('conversation', template: 'conversations/show',
                                                                    locals: { conversation: @conversation })
        end
      end
      return
    end

    begin
      # Start conversation and perform first round
      @conversation.start!
      @conversation.perform_round!

      respond_to do |format|
        format.html { redirect_to @conversation, notice: 'Conversation started and first round completed!' }
        format.turbo_stream { redirect_to @conversation }
      end
    rescue StandardError => e
      Rails.logger.error "[CONTROLLER] Start conversation failed for conversation ##{@conversation.id}: #{e.message}"
      Rails.logger.error "[CONTROLLER] Start conversation error backtrace: #{e.backtrace.join("\n")}"
      @conversation.fail!
      Rails.logger.error "Failed to start conversation: #{e.message}"
      respond_to do |format|
        format.html { redirect_to @conversation, alert: "Failed to start conversation: #{e.message}" }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace('conversation', template: 'conversations/show',
                                                                    locals: { conversation: @conversation })
        end
      end
    end
  end

  def continue
    @conversation = current_user.conversations
                                .includes(:participants)
                                .find(params[:id])

    if @conversation.ready_for_next_round?
      begin
        # Set to in_progress when starting the round
        @conversation.update!(status: :in_progress)

        # Perform entire round (all participants speak)
        @conversation.perform_round!

        respond_to do |format|
          format.html { redirect_to @conversation, notice: 'Round completed!' }
          format.turbo_stream { redirect_to @conversation }
        end
      rescue StandardError => e
        Rails.logger.error "[CONTROLLER] Continue conversation failed for conversation ##{@conversation.id}: #{e.message}"
        Rails.logger.error "[CONTROLLER] Continue conversation error backtrace: #{e.backtrace.join("\n")}"
        @conversation.fail!
        Rails.logger.error "Failed to continue conversation: #{e.message}"
        respond_to do |format|
          format.html { redirect_to @conversation, alert: "Failed to continue conversation: #{e.message}" }
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace('conversation', template: 'conversations/show',
                                                                      locals: { conversation: @conversation })
          end
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to @conversation, alert: 'Conversation cannot continue.' }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace('conversation', template: 'conversations/show',
                                                                    locals: { conversation: @conversation })
        end
      end
    end
  end

  def restart
    @conversation = current_user.conversations.find(params[:id])

    # Delete all messages
    @conversation.messages.destroy_all

    # Reset status if it was complete or failed, otherwise keep as is
    @conversation.update(status: :pending, current_round: 1) if @conversation.complete? || @conversation.failed?

    # Optionally, reset other specific attributes if needed, e.g., current_round if stored explicitly
    # For now, deleting messages effectively resets the round count as it's calculated.

    redirect_to @conversation, notice: 'Conversation has been restarted.'
  end

  def destroy
    @conversation = current_user.conversations.find(params[:id])

    # Optimize deletion by bulk-deleting related records first
    conversation_id = @conversation.id

    # Bulk delete messages (fastest approach)
    Message.where(conversation_id: conversation_id).delete_all

    # Bulk delete participants
    ConversationParticipant.where(conversation_id: conversation_id).delete_all

    # Now delete the conversation (no cascade needed)
    @conversation.delete

    respond_to do |format|
      format.html { redirect_to conversations_path, notice: 'Conversation was successfully deleted.' }
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove("conversation-card-#{conversation_id}")
      end
    end
  end

  private

  def handle_creation_failure
    # Log detailed errors for debugging
    Rails.logger.error '=== CONVERSATION CREATION FAILED ==='
    Rails.logger.error "Conversation errors: #{@conversation.errors.full_messages}"
    @conversation.participants.each_with_index do |participant, index|
      Rails.logger.error "Participant #{index + 1} errors: #{participant.errors.full_messages}" if participant.errors.any?
    end
    Rails.logger.error "Received params: #{conversation_params.inspect}"

    # Add flash message with errors
    flash.now[:alert] = "Failed to create conversation: #{@conversation.errors.full_messages.join(', ')}"

    @available_models = get_available_models
    render :new, status: :unprocessable_entity
  end

  def conversation_params
    params.require(:conversation).permit(
      :max_rounds, :conversation_topic, :dialogue_instructions,
      participants_attributes: %i[id name model_id turn_order system_prompt character_prompt _destroy]
    )
  end

  def get_available_models
    # Curated list of supported models via OpenRouter
    # Update this list manually when new models become available
    [
      { value: 'openai/gpt-4o', text: 'OpenAI: GPT-4o' },
      { value: 'openai/gpt-4o-mini', text: 'OpenAI: GPT-4o Mini' },
      { value: 'anthropic/claude-3-5-sonnet', text: 'Anthropic: Claude 3.5 Sonnet' },
      { value: 'anthropic/claude-3-haiku', text: 'Anthropic: Claude 3 Haiku' },
      { value: 'anthropic/claude-3-opus', text: 'Anthropic: Claude 3 Opus' },
      { value: 'google/gemini-pro-1.5', text: 'Google: Gemini Pro 1.5' },
      { value: 'google/gemini-flash-1.5', text: 'Google: Gemini Flash 1.5' },
      { value: 'meta-llama/llama-3.1-405b-instruct', text: 'Meta: Llama 3.1 405B' },
      { value: 'meta-llama/llama-3.1-70b-instruct', text: 'Meta: Llama 3.1 70B' },
      { value: 'deepseek/deepseek-r1-0528', text: 'DeepSeek: R1 0528' },
      { value: 'mistral/mistral-large', text: 'Mistral: Large' },
      { value: 'cohere/command-r-plus', text: 'Cohere: Command R+' }
    ]
  end
end
