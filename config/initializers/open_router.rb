# frozen_string_literal: true

require 'open_router'

OpenRouter.configure do |config|
  config.access_token = ENV.fetch('OPENROUTER_API_KEY', nil)
  # Optional: customize base URL for proxies like Helicone
  # Note: Do not include /v1 in base URL as it's added automatically
  config.uri_base = ENV.fetch('OPENROUTER_BASE_URL', 'https://openrouter.ai/api')
  # Optional: customize timeout if needed
  # config.request_timeout = 120
end

Rails.logger.info 'OpenRouter configured successfully'
