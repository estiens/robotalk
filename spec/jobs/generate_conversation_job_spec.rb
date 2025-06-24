require 'rails_helper'

RSpec.describe GenerateConversationJob, type: :job, vcr: true do
  include AuthenticationHelpers
  include ActiveJob::TestHelper
  describe '#perform' do
    context 'golden path: full conversation generation' do
      it 'generates a complete conversation from start to finish via background job', :vcr do
        VCR.use_cassette('GenerateConversationJob/generates_complete_conversation', record: :new_episodes) do
          # Create a user and conversation
          user = create_user
          conversation = Conversation.create!(
            user: user,
            conversation_topic: 'The impact of renewable energy on global climate goals',
            dialogue_instructions: 'Discuss the role of renewable energy in achieving climate targets, exploring both benefits and challenges.',
            max_rounds: 5,
            status: :generating,
            participants_attributes: [
              { model_id: 'openai/gpt-4o-mini', turn_order: 1, name: 'Climate Scientist',
                character_prompt: 'You are a climate scientist focused on data-driven analysis.' },
              { model_id: 'anthropic/claude-3-haiku', turn_order: 2, name: 'Energy Policy Expert',
                character_prompt: 'You are an energy policy expert focused on practical implementation.' }
            ]
          )

          # Verify initial state
          expect(conversation.status).to eq('generating')
          expect(conversation.messages.count).to eq(0)
          expect(conversation.current_round).to eq(0)

          # Execute the job
          perform_enqueued_jobs do
            GenerateConversationJob.perform_later(conversation)
          end

          # Reload to get updated state
          conversation.reload

          # Verify final conversation state
          expect(conversation.status).to eq('complete')
          expect(conversation.current_round).to eq(5)

          # Verify message structure
          messages = conversation.messages.order(:created_at)

          # Should have system messages for each participant (2) + messages from acts_as_chat
          expect(messages.count).to be >= 7

          # System messages should be present
          system_messages = messages.where(role: 'system')
          expect(system_messages.count).to eq(2)

          system_messages.each do |msg|
            expect(msg.content).to include(conversation.conversation_topic)
            expect(msg.model_id).to be_in(conversation.participants.pluck(:model_id))
          end

          # Should have 5 assistant messages (one per round)
          assistant_messages = messages.where(role: 'assistant').order(:created_at)
          expect(assistant_messages.count).to eq(5)

          # Verify that all assistant messages have content and model_id
          assistant_messages.each_with_index do |message, index|
            expect(message.content).to be_present
            expect(message.content.length).to be > 30 # Ensure substantial responses
            expect(message.model_id).to be_present
            expect(message.model_id).to be_in(conversation.participants.pluck(:model_id))
          end

          # Verify conversation flows logically
          # First message should be introductory
          first_message = assistant_messages.first
          expect(first_message.content.downcase).to match(/climate|energy|renewable|scientist/)

          # Subsequent messages should reference previous discussion
          assistant_messages[1..-1].each do |message|
            # Each response should be contextually relevant (basic check)
            expect(message.content.length).to be > 30
          end

          # Verify participant names are preserved
          climate_participant = conversation.participants.find_by(name: 'Climate Scientist')
          policy_participant = conversation.participants.find_by(name: 'Energy Policy Expert')

          expect(climate_participant.model_id).to eq('openai/gpt-4o-mini')
          expect(policy_participant.model_id).to eq('anthropic/claude-3-haiku')

          # Verify metadata tracking
          assistant_messages.each do |message|
            if message.metadata.present?
              expect(message.metadata).to be_a(Hash)
              # May include response_time_ms, model info, etc.
            end
          end
        end
      end

      it 'handles job failure gracefully' do
        user = create_user
        conversation = Conversation.create!(
          user: user,
          conversation_topic: 'Test topic',
          max_rounds: 3,
          status: :generating,
          participants_attributes: [
            { model_id: 'invalid/model', turn_order: 1, name: 'Test Bot 1' },
            { model_id: 'invalid/model2', turn_order: 2, name: 'Test Bot 2' }
          ]
        )

        # Mock the conversation to raise an error
        allow(conversation).to receive(:generate_full_conversation!).and_raise(StandardError.new('API Error'))

        # Execute the job
        perform_enqueued_jobs do
          GenerateConversationJob.perform_later(conversation)
        end

        # Should mark conversation as failed
        conversation.reload
        expect(conversation.status).to eq('failed')
      end

      it 'respects max_rounds limit' do
        user = create_user
        conversation = Conversation.create!(
          user: user,
          conversation_topic: 'Short test conversation',
          max_rounds: 2,
          status: :generating,
          participants_attributes: [
            { model_id: 'openai/gpt-4o-mini', turn_order: 1, name: 'Bot 1' },
            { model_id: 'anthropic/claude-3-haiku', turn_order: 2, name: 'Bot 2' }
          ]
        )

        VCR.use_cassette('GenerateConversationJob/respects_max_rounds', record: :new_episodes) do
          perform_enqueued_jobs do
            GenerateConversationJob.perform_later(conversation)
          end

          conversation.reload
          expect(conversation.status).to eq('complete')
          expect(conversation.current_round).to eq(2)
          expect(conversation.messages.where(role: 'assistant').count).to eq(2)
        end
      end

      it 'creates appropriate system messages for each participant' do
        user = create_user
        conversation = Conversation.create!(
          user: user,
          conversation_topic: 'System message test',
          max_rounds: 1,
          status: :generating,
          participants_attributes: [
            {
              model_id: 'openai/gpt-4o-mini',
              turn_order: 1,
              name: 'Custom Bot',
              character_prompt: 'You are a helpful assistant with a unique personality.'
            },
            {
              model_id: 'anthropic/claude-3-haiku',
              turn_order: 2,
              name: 'Another Bot',
              character_prompt: 'You are a different assistant with specific expertise.'
            }
          ]
        )

        VCR.use_cassette('GenerateConversationJob/creates_system_messages', record: :new_episodes) do
          perform_enqueued_jobs do
            GenerateConversationJob.perform_later(conversation)
          end

          conversation.reload
          system_messages = conversation.messages.where(role: 'system')

          expect(system_messages.count).to eq(2)

          system_messages.each do |msg|
            expect(msg.content).to include(conversation.conversation_topic)
            expect(msg.content).to include('Custom Bot') if msg.model_id == 'openai/gpt-4o-mini'
            expect(msg.content).to include('Another Bot') if msg.model_id == 'anthropic/claude-3-haiku'
          end
        end
      end
    end
  end
end
