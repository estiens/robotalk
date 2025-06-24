# Streaming Configuration
# Set to false to disable streaming features and use basic conversation generation
# Can be controlled via STREAMING_ENABLED environment variable (defaults to true)
Rails.application.config.streaming_enabled = ENV.fetch("STREAMING_ENABLED", "true").downcase == "true"
