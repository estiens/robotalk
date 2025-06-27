# Disable ActionCable broadcasts in tests to avoid rendering views
RSpec.configure do |config|
  config.before(:each, type: :model) do
    # Stub ActionCable broadcasts
    allow(ActionCable.server).to receive(:broadcast).and_return(true)

    # Stub Turbo Stream broadcasts
    allow(Turbo::StreamsChannel).to receive(:broadcast_action_to).and_return(true)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to).and_return(true)
    allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to).and_return(true)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_return(true)
    allow(Turbo::StreamsChannel).to receive(:broadcast_update_to).and_return(true)
    allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to).and_return(true)
    allow(Turbo::StreamsChannel).to receive(:broadcast_before_to).and_return(true)
    allow(Turbo::StreamsChannel).to receive(:broadcast_after_to).and_return(true)

    # Stub any remaining broadcast callback methods (most have been removed)
    # Since we removed most broadcasts_to from Message, this is mostly for safety
  end

  config.after(:each, type: :model) do
    # Cleanup is handled by RSpec's automatic mock cleanup
  end
end
