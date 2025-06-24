require 'vcr'

VCR.configure do |config|
  config.cassette_library_dir = "spec/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Filter out sensitive data
  config.filter_sensitive_data('<OPENROUTER_API_KEY>') { ENV['OPENROUTER_API_KEY'] }
  config.filter_sensitive_data('<OPENAI_API_KEY>') { ENV['OPENAI_API_KEY'] }
  config.filter_sensitive_data('<ANTHROPIC_API_KEY>') { ENV['ANTHROPIC_API_KEY'] }

  # Allow HTTP connections when no cassette is in use (for Capybara server)
  config.allow_http_connections_when_no_cassette = true

  # Record new episodes for new interactions
  # Can be overridden with VCR_RECORD_MODE environment variable
  record_mode = ENV['VCR_RECORD_MODE']&.to_sym || :new_episodes
  config.default_cassette_options = {
    record: record_mode,
    match_requests_on: [ :method, :uri, :body ],
    # Ensure we don't accidentally make real requests
    allow_playback_repeats: true,
    # Preserve exact matching for better test reliability
    preserve_exact_body_bytes: true
  }

  # Ignore requests to localhost for Capybara and other test infrastructure
  config.ignore_request do |request|
    uri = URI.parse(request.uri)
    # Ignore localhost requests (Capybara server, test infrastructure, etc.)
    uri.host == '127.0.0.1' || uri.host == 'localhost'
  end
end
