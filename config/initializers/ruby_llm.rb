require "ruby_llm"

RubyLLM.configure do |config|
  # --- Provider API Keys ---
  # Provide keys ONLY for the providers you intend to use.
  # Using environment variables (ENV.fetch) is highly recommended.
  # config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)
  # config.openai_organization_id = ENV.fetch("OPENAI_ORGANIZATION_ID", nil)
  # config.openai_project_id = ENV.fetch("OPENAI_PROJECT_ID", nil)
  # config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
  # config.gemini_api_key = ENV.fetch("GEMINI_API_KEY", nil)
  # config.deepseek_api_key = ENV.fetch("DEEPSEEK_API_KEY", nil)
  config.openrouter_api_key = ENV.fetch("OPENROUTER_API_KEY", nil)
end

# RubyLLM handles caching internally, so no need for additional caching here
Rails.logger.info "RubyLLM configured successfully"
