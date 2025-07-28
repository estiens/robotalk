# frozen_string_literal: true

module ConversationsHelper
  def model_name_for_id(model_identifier)
    model = RubyLLM::Models.all.find { |m| m.id == model_identifier }
    model&.name || model_identifier
  rescue StandardError => e
    Rails.logger.error "Failed to find model name for #{model_identifier}: #{e.message}"
    model_identifier
  end

  def friendly_model_name(model_identifier)
    model_name_for_id(model_identifier)
  end

  def model_avatar_emoji(model_identifier)
    case model_identifier
    when /openai/
      '🤖'
    when /anthropic/
      '🧠'
    when /google/
      '💎'
    when /meta-llama/
      '🦙'
    else
      '🔮'
    end
  end

  def model_color_class(model_identifier, turn_order = 1)
    # Color palettes for different turn orders
    color_sets = [
      # Turn order 1
      {
        openai: { bg: 'bg-blue-50', border: 'border-blue-200', content: 'bg-blue-100', accent: 'border-blue-500' },
        anthropic: { bg: 'bg-orange-50', border: 'border-orange-200', content: 'bg-orange-100',
                     accent: 'border-orange-500' },
        google: { bg: 'bg-purple-50', border: 'border-purple-200', content: 'bg-purple-100',
                  accent: 'border-purple-500' },
        meta: { bg: 'bg-indigo-50', border: 'border-indigo-200', content: 'bg-indigo-100',
                accent: 'border-indigo-500' },
        default: { bg: 'bg-blue-50', border: 'border-blue-200', content: 'bg-blue-100', accent: 'border-blue-500' }
      },
      # Turn order 2
      {
        openai: { bg: 'bg-cyan-50', border: 'border-cyan-200', content: 'bg-cyan-100', accent: 'border-cyan-500' },
        anthropic: { bg: 'bg-amber-50', border: 'border-amber-200', content: 'bg-amber-100',
                     accent: 'border-amber-500' },
        google: { bg: 'bg-pink-50', border: 'border-pink-200', content: 'bg-pink-100', accent: 'border-pink-500' },
        meta: { bg: 'bg-violet-50', border: 'border-violet-200', content: 'bg-violet-100',
                accent: 'border-violet-500' },
        default: { bg: 'bg-green-50', border: 'border-green-200', content: 'bg-green-100', accent: 'border-green-500' }
      },
      # Turn order 3+
      {
        openai: { bg: 'bg-slate-50', border: 'border-slate-200', content: 'bg-slate-100', accent: 'border-slate-500' },
        anthropic: { bg: 'bg-stone-50', border: 'border-stone-200', content: 'bg-stone-100',
                     accent: 'border-stone-500' },
        google: { bg: 'bg-zinc-50', border: 'border-zinc-200', content: 'bg-zinc-100', accent: 'border-zinc-500' },
        meta: { bg: 'bg-neutral-50', border: 'border-neutral-200', content: 'bg-neutral-100',
                accent: 'border-neutral-500' },
        default: { bg: 'bg-gray-50', border: 'border-gray-200', content: 'bg-gray-100', accent: 'border-gray-500' }
      }
    ]

    # Select color set based on turn order (max 3 sets)
    color_set_index = [turn_order - 1, 2].min
    color_set = color_sets[color_set_index]

    # Select colors based on provider
    provider_key = case model_identifier
                   when /openai/ then :openai
                   when /anthropic/ then :anthropic
                   when /google/ then :google
                   when /meta-llama/ then :meta
                   else :default
                   end

    color_set[provider_key]
  end

  def participant_class(participant)
    "participant-#{participant.turn_order}"
  end

  def conversation_has_content_issues?(conversation)
    conversation.messages.where(role: 'assistant').any? { |m| m.content.blank? }
  end

  def content_missing_count(conversation)
    conversation.messages.where(role: 'assistant').count { |m| m.content.blank? }
  end

  def smart_truncate_message(content, max_length: 800)
    return content if content.length <= max_length

    # Find a good breaking point near the max length
    # Look for sentence endings first (. ! ?)
    sentence_endings = ['. ', '! ', '? ']
    
    # Try to find the last sentence ending before max_length
    best_break = 0
    sentence_endings.each do |ending|
      content[0...max_length].split(ending).tap do |parts|
        if parts.length > 1
          # Reconstruct up to the last complete sentence
          candidate_break = parts[0...-1].join(ending).length + ending.length
          best_break = [best_break, candidate_break].max
        end
      end
    end
    
    # If no sentence break found, try paragraph breaks
    if best_break == 0
      paragraph_break = content[0...max_length].rindex("\n\n")
      best_break = paragraph_break + 2 if paragraph_break
    end
    
    # If still no good break, try single line breaks
    if best_break == 0
      line_break = content[0...max_length].rindex("\n")
      best_break = line_break + 1 if line_break
    end
    
    # If still no break found, try word boundaries
    if best_break == 0
      word_break = content[0...max_length].rindex(' ')
      best_break = word_break + 1 if word_break
    end
    
    # Fallback to character truncation if all else fails
    break_point = best_break > 0 ? best_break : max_length
    
    content[0...break_point].rstrip
  end
end
