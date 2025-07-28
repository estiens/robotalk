# frozen_string_literal: true

module ApplicationHelper
  DAISYUI_THEMES = %w[
    light dark cupcake bumblebee emerald corporate synthwave retro cyberpunk valentine
    halloween garden forest aqua lofi pastel fantasy wireframe black luxury dracula
    cmyk autumn business acid lemonade night coffee winter dim nord sunset
  ].freeze

  def available_themes
    DAISYUI_THEMES
  end

  def conversation_has_content_issues?(conversation)
    conversation.messages.any? { |m| m.content.blank? }
  end

  def content_missing_count(conversation)
    conversation.messages.count { |m| m.content.blank? }
  end

  def conversation_debug_info(conversation)
    {
      total_messages: conversation.messages.count,
      system_messages: conversation.messages.where(role: 'system').count,
      assistant_messages: conversation.messages.where(role: 'assistant').count,
      content_missing: content_missing_count(conversation),
      participants: conversation.participants.count,
      current_round: conversation.current_round,
      max_rounds: conversation.max_rounds,
      can_continue: conversation.can_continue?
    }
  end

  def flash_class(level)
    case level.to_sym
    when :notice then 'alert alert-info'
    when :success then 'alert alert-success'
    when :error then 'alert alert-error'
    when :alert then 'alert alert-warning'
    else 'alert'
    end
  end

  def dialogue_types_for_select
    ConversationTemplates.dialogue_types_by_category.map do |category, types|
      [category, types.map { |key, data| [data[:name], key] }]
    end
  end

  def character_archetypes_for_select
    ConversationTemplates.characters_by_category.map do |category, characters|
      [category, characters.map { |key, data| [data[:name], key] }]
    end
  end

  def suggested_combinations_for_select
    ConversationTemplates::SUGGESTED_COMBINATIONS.map do |combo|
      [
        "#{combo[:name]} - #{combo[:description_detail]}",
        combo[:name],
        {
          'data-dialogue-type' => combo[:dialogue_type],
          'data-participant1-character' => combo[:participant_1_character],
          'data-participant2-character' => combo[:participant_2_character]
        }
      ]
    end
  end
end
