# frozen_string_literal: true

class ModelsController < ApplicationController
  def index
    @models = get_available_models.map do |model|
      OpenStruct.new(
        id: model[:value],
        name: model[:text]
      )
    end
  end

  private

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
