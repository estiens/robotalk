class ConversationsController < ApplicationController
  before_action :require_user
  def index
    @conversations = current_user.conversations.order(created_at: :desc)
  end

  def show
    @conversation = current_user.conversations.find(params[:id])
  end

  def edit
    @conversation = current_user.conversations.find(params[:id])
    @available_models = get_available_models
  end

  def update
    @conversation = current_user.conversations.find(params[:id])

    if @conversation.update(conversation_params)
      redirect_to @conversation, notice: "Conversation updated successfully!"
    else
      @available_models = get_available_models
      render :edit, status: :unprocessable_entity
    end
  end

  def debug
    @conversation = current_user.conversations.find(params[:id])
    render json: {
      conversation: {
        id: @conversation.id,
        topic: @conversation.conversation_topic,
        dialogue_instructions: @conversation.dialogue_instructions,
        max_rounds: @conversation.max_rounds,
        current_round: @conversation.current_round,
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

  def new
    @conversation = current_user.conversations.build
    # Build two default participants
    # Build two default participants with a default model
    2.times do |i|
      participant = @conversation.participants.build
      # Set default model for the participant
      participant.model_id = "deepseek/deepseek-r1-0528"
    end
    @available_models = get_available_models
  end

  def create
    @conversation = current_user.conversations.build(conversation_params)

    if params[:generate_in_background]
      @conversation.status = :generating
      if @conversation.save
        GenerateConversationJob.perform_later(@conversation)
        redirect_to conversations_path, notice: "Conversation is being generated in the background."
      else
        handle_creation_failure
      end
    else
      @conversation.status = :interactive
      if @conversation.save
        redirect_to @conversation, notice: "Conversation created successfully! You can now start it."
      else
        handle_creation_failure
      end
    end
  end

  def start
    @conversation = current_user.conversations.find(params[:id])

    unless @conversation.can_start?
      alert_message = @conversation.interactive? ? "Conversation must have at least 2 participants to start." : "This conversation is not interactive."
      respond_to do |format|
        format.html { redirect_to @conversation, alert: alert_message }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("conversation", template: "conversations/show", locals: { conversation: @conversation }) }
      end
      return
    end

    # System messages will be created by ruby_llm via with_instructions

    begin
      # Always use streaming
      next_speaker_model = @conversation.next_speaker
      ChatStreamJob.perform_later(@conversation.id)

      respond_to do |format|
        format.html { redirect_to @conversation, notice: "Conversation started with streaming!" }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.update("message-loading",
              html: render_to_string(partial: "shared/streaming_indicator", locals: { model_name: next_speaker_model }),
              attributes: { class: "mt-8 loading-indicator-chat animate-fade-in" }),
            turbo_stream.replace("start-conversation-controls", "")
          ]
        end
      end
    rescue => e
      Rails.logger.error "Failed to start conversation: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      respond_to do |format|
        format.html { redirect_to @conversation, alert: "Failed to start conversation: #{e.message}" }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("conversation", template: "conversations/show", locals: { conversation: @conversation }) }
      end
    end
  end

  def continue
    @conversation = current_user.conversations.find(params[:id])

    if @conversation.can_continue?
      # Always use streaming
      ChatStreamJob.perform_later(@conversation.id)

      respond_to do |format|
        format.html { redirect_to @conversation, notice: "Conversation continued with streaming!" }
        format.turbo_stream { head :ok } # The broadcasts from the model will handle UI updates.
      end
    else
      respond_to do |format|
        format.html { redirect_to @conversation, alert: "Conversation cannot continue." }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("conversation", template: "conversations/show", locals: { conversation: @conversation }) }
      end
    end
  end

  def restart
    @conversation = current_user.conversations.find(params[:id])

    # Delete all messages
    @conversation.messages.destroy_all

    # Reset status if it was complete or failed, otherwise keep as is (e.g. interactive)
    if @conversation.complete? || @conversation.failed?
      @conversation.update(status: :interactive)
    end

    # Optionally, reset other specific attributes if needed, e.g., current_round if stored explicitly
    # For now, deleting messages effectively resets the round count as it's calculated.

    redirect_to @conversation, notice: "Conversation has been restarted."
  end

  private

  def handle_creation_failure
    # Log detailed errors for debugging
    Rails.logger.error "=== CONVERSATION CREATION FAILED ==="
    Rails.logger.error "Conversation errors: #{@conversation.errors.full_messages}"
    @conversation.participants.each_with_index do |participant, index|
      if participant.errors.any?
        Rails.logger.error "Participant #{index + 1} errors: #{participant.errors.full_messages}"
      end
    end
    Rails.logger.error "Received params: #{conversation_params.inspect}"

    # Add flash message with errors
    flash.now[:alert] = "Failed to create conversation: #{@conversation.errors.full_messages.join(', ')}"

    @available_models = get_available_models
    render :new, status: :unprocessable_entity
  end

  def conversation_params
    params.require(:conversation).permit(:max_rounds, :conversation_topic, :dialogue_instructions,
      participants_attributes: [ :model_id, :system_prompt, :character_prompt, :turn_order, :name ])
  end

  def get_available_models
    RubyLLM::Models.all.sort_by { |model| model.created_at || Time.at(0) }.reverse.map do |model|
      { value: model.id, text: model.name }
    end
  rescue => e
    Rails.logger.error "Failed to load models: #{e.message}"
    # Fallback to hardcoded models if everything fails (original list)
    [
      { value: "openai/gpt-4o", text: "OpenAI: GPT-4o" },
      { value: "openai/gpt-4o-mini", text: "OpenAI: GPT-4o Mini" },
      { value: "anthropic/claude-3-5-sonnet", text: "Anthropic: Claude 3.5 Sonnet" },
      { value: "anthropic/claude-3-haiku", text: "Anthropic: Claude 3 Haiku" },
      { value: "deepseek/deepseek-r1-0528", text: "DeepSeek: R1 0528 (OpenRouter)" } # Ensure DeepSeek is an option
    ]
  end
end
