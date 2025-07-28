# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GenerateConversationJob, :vcr do
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
          expect(conversation.current_round).to eq(1)

          # Execute the job
          perform_enqueued_jobs do
            GenerateConversationJob.perform_later(conversation)
          end

          # Reload to get updated state
          conversation.reload

          # Verify final conversation state
          expect(conversation.status).to eq('complete')
          expect(conversation.current_round).to eq(6) # Past max_rounds

          # Verify message structure - all messages are assistant messages now
          messages = conversation.messages.order(:created_at)
          expect(messages.count).to eq(10) # 2 participants × 5 rounds = 10 messages

          # All messages should be assistant messages in the simplified system
          expect(messages.pluck(:role).uniq).to eq(['assistant'])

          # Verify that all messages have content and model_id
          messages.each do |message|
            expect(message.content).to be_present
            expect(message.content.length).to be > 10 # Ensure responses have content
            expect(message.model_id).to be_present
            expect(message.model_id).to be_in(conversation.participants.pluck(:model_id))
            expect(message.round_number).to be_between(1, 5)
          end

          # Verify conversation flows logically
          # First message should be relevant to the topic
          first_message = messages.first
          expect(first_message.content.downcase).to match(/climate|energy|renewable/)

          # Subsequent messages should be substantial
          messages[1..].each do |message|
            # Each response should be contextually relevant (basic check)
            expect(message.content.length).to be > 10
          end

          # Verify participant names are preserved
          climate_participant = conversation.participants.find_by(name: 'Climate Scientist')
          policy_participant = conversation.participants.find_by(name: 'Energy Policy Expert')

          expect(climate_participant.model_id).to eq('openai/gpt-4o-mini')
          expect(policy_participant.model_id).to eq('anthropic/claude-3-haiku')

          # Verify metadata tracking
          messages.each do |message|
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

        # Mock the Conversation model to raise an error during conversation generation
        allow_any_instance_of(Conversation).to receive(:generate_full_conversation!).and_raise(StandardError.new('API Error'))

        # Execute the job - we expect it to fail, but don't care about the exact error
        # The important part is the side effect: conversation should be marked as failed
        # Create and perform the job directly instead of using ActiveJob test helpers
        job = GenerateConversationJob.new

        # We expect an error, but what we really care about is that the conversation is marked as failed
        expect { job.perform(conversation) }.to raise_error(StandardError, /API Error/)

        # Should mark conversation as failed before re-raising the error
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
          expect(conversation.current_round).to eq(3) # Past max_rounds
          expect(conversation.messages.count).to eq(4) # 2 participants × 2 rounds
        end
      end

      it 'creates conversation responses with participant characteristics' do
        user = create_user
        conversation = Conversation.create!(
          user: user,
          conversation_topic: 'Personality test',
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

        VCR.use_cassette('GenerateConversationJob/creates_messages_with_characteristics', record: :new_episodes) do
          perform_enqueued_jobs do
            GenerateConversationJob.perform_later(conversation)
          end

          conversation.reload
          messages = conversation.messages.order(:created_at)

          expect(messages.count).to eq(2) # 2 participants × 1 round

          # Verify each message has proper participant association
          messages.each do |msg|
            expect(msg.conversation_participant).to be_present
            expect(msg.content).to be_present
            expect(msg.content.length).to be > 10
            expect(msg.role).to eq('assistant')
          end
        end
      end
    end
  end
end
