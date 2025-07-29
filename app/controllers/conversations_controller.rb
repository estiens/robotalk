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
                                .includes(:participants, :messages, :rounds)
                                .find(params[:id])
    render json: {
      conversation: {
        id: @conversation.id,
        topic: @conversation.conversation_topic,
        dialogue_instructions: @conversation.dialogue_instructions,
        max_rounds: @conversation.max_rounds,
        current_round: @conversation.current_round_number,
        can_continue: @conversation.can_continue?,
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
      rounds: @conversation.rounds.map do |r|
        {
          id: r.id,
          number: r.number,
          status: r.status,
          started_at: r.started_at,
          completed_at: r.completed_at,
          failed_at: r.failed_at,
          progress_percentage: r.progress_percentage,
          messages_count: r.messages.count
        }
      end,
      messages: @conversation.messages.map do |m|
        {
          id: m.id,
          round_id: m.round_id,
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
      # Create first round and start it
      round = @conversation.rounds.create!(number: 1)
      
      # Execute round with interactive UI updates
      result = InteractiveRoundRunner.new(round).execute
      round = result[:round] # Get updated round state
      
      if round.execution_successful?
        Rails.logger.info "[CONTROLLER] First round completed for conversation ##{@conversation.id}"
        respond_to do |format|
          format.html { redirect_to @conversation, notice: 'Conversation started and first round completed!' }
          format.turbo_stream { redirect_to @conversation }
        end
      else
        raise StandardError, "Round execution failed with status: #{round.status}"
      end
    rescue StandardError => e
      Rails.logger.error "[CONTROLLER] Start conversation failed for conversation ##{@conversation.id}: #{e.message}"
      Rails.logger.error "[CONTROLLER] Start conversation error backtrace: #{e.backtrace.join("\n")}"
      
      # Mark round as failed if it exists
      round&.fail!(e.message)
      
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
                                .includes(:participants, :rounds)
                                .find(params[:id])

    # Check if we can continue based on max_rounds and current progress
    unless @conversation.can_continue?
      respond_to do |format|
        format.html { redirect_to @conversation, alert: 'Conversation has reached maximum rounds.' }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace('conversation', template: 'conversations/show',
                                                                    locals: { conversation: @conversation })
        end
      end
      return
    end

    begin
      # Create next round
      next_round_number = @conversation.current_round_number + 1
      round = @conversation.rounds.create!(number: next_round_number)
      
      # Execute round with interactive UI updates
      result = InteractiveRoundRunner.new(round).execute
      round = result[:round] # Get updated round state
      
      if round.execution_successful?
        Rails.logger.info "[CONTROLLER] Round #{next_round_number} completed for conversation ##{@conversation.id}"
        respond_to do |format|
          format.html { redirect_to @conversation, notice: 'Round completed!' }
          format.turbo_stream do
            # No redirect needed - streaming updates handle UI changes
            head :ok
          end
        end
      else
        raise StandardError, "Round execution failed with status: #{round.status}"
      end
    rescue StandardError => e
      Rails.logger.error "[CONTROLLER] Continue conversation failed for conversation ##{@conversation.id}: #{e.message}"
      Rails.logger.error "[CONTROLLER] Continue conversation error backtrace: #{e.backtrace.join("\n")}"
      
      # Mark round as failed if it exists
      round&.fail!(e.message)

      respond_to do |format|
        format.html { redirect_to @conversation, alert: "Failed to continue conversation: #{e.message}" }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace('conversation', template: 'conversations/show',
                                                                    locals: { conversation: @conversation })
        end
      end
    end
  end

  def restart
    @conversation = current_user.conversations.find(params[:id])

    # Delete all rounds (which will cascade delete messages due to dependent: :destroy)
    @conversation.rounds.destroy_all

    redirect_to @conversation, notice: 'Conversation has been restarted.'
  end

  def destroy
    @conversation = current_user.conversations.find(params[:id])
    conversation_id = @conversation.id

    # The Conversation model has dependent: :destroy on rounds and participants
    # which will cascade delete messages automatically through rounds
    @conversation.destroy

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
