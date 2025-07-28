# frozen_string_literal: true

require 'vcr'

VCR.configure do |config|
  config.cassette_library_dir = 'spec/vcr_cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Filter out sensitive data
  config.filter_sensitive_data('<OPENROUTER_API_KEY>') { ENV.fetch('OPENROUTER_API_KEY', nil) }
  config.filter_sensitive_data('<OPENAI_API_KEY>') { ENV.fetch('OPENAI_API_KEY', nil) }
  config.filter_sensitive_data('<ANTHROPIC_API_KEY>') { ENV.fetch('ANTHROPIC_API_KEY', nil) }
  config.filter_sensitive_data('<GEMINI_API_KEY>') { ENV.fetch('GEMINI_API_KEY', nil) }
  config.filter_sensitive_data('<DEEPSEEK_API_KEY>') { ENV.fetch('DEEPSEEK_API_KEY', nil) }

  # STRICT MODE: Prevent external API calls outside of VCR cassettes
  # This ensures all external API calls are either recorded or replayed
  config.allow_http_connections_when_no_cassette = false

  # Use :once mode for strict recording - record if cassette doesn't exist,
  # error if trying to make new requests when cassette exists
  record_mode = case ENV['VCR_RECORD_MODE']&.to_sym
                when :all then :all       # Re-record everything
                when :none then :none     # Never record, only replay
                when :new_episodes then :new_episodes # Add new interactions to existing cassettes
                else :once # Default: record once, then replay
                end

  config.default_cassette_options = {
    record: record_mode,
    # Strict request matching to prevent cassette mismatches
    match_requests_on: %i[method uri body headers],
    allow_playback_repeats: true,
    preserve_exact_body_bytes: true,
    # Serialize with YAML for better readability and debugging
    serialize_with: :yaml,
    # Allow unused HTTP interactions to prevent test failures
    allow_unused_http_interactions: true
  }

  # Ignore local test infrastructure requests
  config.ignore_request do |request|
    uri = URI.parse(request.uri)
    # Ignore localhost requests (Capybara server, Selenium WebDriver, etc.)
    ['127.0.0.1', 'localhost'].include?(uri.host)
  end

  # Add better error messages for unhandled requests
  config.before_record do |interaction|
    puts "🎬 VCR: Recording NEW interaction with #{interaction.request.uri}"
    puts "   Method: #{interaction.request.method}"
    puts "   Headers: #{interaction.request.headers.keys.join(', ')}"
  end

  config.before_playback do |interaction|
    puts "▶️  VCR: Playing back recorded interaction with #{interaction.request.uri}"
  end
end
