# frozen_string_literal: true

# Disable ActionCable broadcasts in tests to avoid rendering views
RSpec.configure do |config|
  config.before(:each, type: :model) do
    # Stub ActionCable broadcasts
    allow(ActionCable.server).to receive(:broadcast).and_return(true)

    # Stub Turbo Stream broadcasts
    allow(Turbo::StreamsChannel).to receive_messages(broadcast_action_to: true, broadcast_append_to: true,
                                                     broadcast_prepend_to: true, broadcast_replace_to: true, broadcast_update_to: true, broadcast_remove_to: true, broadcast_before_to: true, broadcast_after_to: true)

    # Stub any remaining broadcast callback methods (most have been removed)
    # Since we removed most broadcasts_to from Message, this is mostly for safety
  end

  config.after(:each, type: :model) do
    # Cleanup is handled by RSpec's automatic mock cleanup
  end
end
