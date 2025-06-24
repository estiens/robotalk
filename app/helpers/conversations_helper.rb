module ConversationsHelper
  def model_name_for_id(model_identifier)
    model = RubyLLM::Models.all.find { |m| m.id == model_identifier }
    model&.name || model_identifier
  rescue => e
    Rails.logger.error "Failed to find model name for #{model_identifier}: #{e.message}"
    model_identifier
  end

  def friendly_model_name(model_identifier)
    model_name_for_id(model_identifier)
  end

  def model_avatar_emoji(model_identifier)
    case model_identifier
    when /openai/
      "🤖"
    when /anthropic/
      "🧠"
    when /google/
      "💎"
    when /meta-llama/
      "🦙"
    else
      "🔮"
    end
  end

  def model_color_class(model_identifier, turn_order = 1)
    # Color palettes for different turn orders
    color_sets = [
      # Turn order 1
      {
        openai: { bg: "bg-blue-50", border: "border-blue-200", content: "bg-blue-100", accent: "border-blue-500" },
        anthropic: { bg: "bg-orange-50", border: "border-orange-200", content: "bg-orange-100", accent: "border-orange-500" },
        google: { bg: "bg-purple-50", border: "border-purple-200", content: "bg-purple-100", accent: "border-purple-500" },
        meta: { bg: "bg-indigo-50", border: "border-indigo-200", content: "bg-indigo-100", accent: "border-indigo-500" },
        default: { bg: "bg-blue-50", border: "border-blue-200", content: "bg-blue-100", accent: "border-blue-500" }
      },
      # Turn order 2
      {
        openai: { bg: "bg-cyan-50", border: "border-cyan-200", content: "bg-cyan-100", accent: "border-cyan-500" },
        anthropic: { bg: "bg-amber-50", border: "border-amber-200", content: "bg-amber-100", accent: "border-amber-500" },
        google: { bg: "bg-pink-50", border: "border-pink-200", content: "bg-pink-100", accent: "border-pink-500" },
        meta: { bg: "bg-violet-50", border: "border-violet-200", content: "bg-violet-100", accent: "border-violet-500" },
        default: { bg: "bg-green-50", border: "border-green-200", content: "bg-green-100", accent: "border-green-500" }
      },
      # Turn order 3+
      {
        openai: { bg: "bg-slate-50", border: "border-slate-200", content: "bg-slate-100", accent: "border-slate-500" },
        anthropic: { bg: "bg-stone-50", border: "border-stone-200", content: "bg-stone-100", accent: "border-stone-500" },
        google: { bg: "bg-zinc-50", border: "border-zinc-200", content: "bg-zinc-100", accent: "border-zinc-500" },
        meta: { bg: "bg-neutral-50", border: "border-neutral-200", content: "bg-neutral-100", accent: "border-neutral-500" },
        default: { bg: "bg-gray-50", border: "border-gray-200", content: "bg-gray-100", accent: "border-gray-500" }
      }
    ]

    # Select color set based on turn order (max 3 sets)
    color_set_index = [ turn_order - 1, 2 ].min
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
end
