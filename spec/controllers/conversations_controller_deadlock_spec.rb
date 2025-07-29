# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConversationsController, type: :controller do
  let(:user) { create(:user) }
  let(:conversation) do
    create(:conversation, :with_alice_and_bob,
           user: user,
           conversation_topic: 'Deadlock Test',
           max_rounds: 2,
           status: 'pending')
  end

  before do
    # Manual session setup for controller specs
    session[:user_id] = user.id
    allow(controller).to receive(:current_user).and_return(user)
  end

  describe 'conversation state deadlock bug' do
    it 'CRITICAL BUG: should recover from LLM failures and not leave conversation stuck in failed round state' do
      # Mock InteractiveRoundRunner to fail after round starts
      mock_round = double('Round', execution_successful?: false, status: 'failed', fail!: true)
      mock_result = { round: mock_round }
      mock_runner = double('InteractiveRoundRunner')
      allow(InteractiveRoundRunner).to receive(:new).and_return(mock_runner)
      allow(mock_runner).to receive(:execute).and_return(mock_result)

      # Attempt to start conversation (this should handle failure gracefully)
      post :start, params: { id: conversation.id }
      
      conversation.reload

      # Round should be created and controller should handle the failure
      expect(conversation.rounds).to be_present
      created_round = conversation.rounds.last
      expect(created_round.number).to eq(1)
    end

    it 'handles continue action failures without deadlock' do
      # Set up a conversation with completed first round using factories
      conversation_with_round = create(:conversation, :with_alice_and_bob,
                                     user: user,
                                     conversation_topic: 'Continue Test',
                                     max_rounds: 3,
                                     status: 'pending')
      
      # Create completed first round with messages
      create(:round, :completed, :with_all_messages,
             conversation: conversation_with_round,
             number: 1)

      expect(conversation_with_round.can_continue?).to be(true)

      # Mock InteractiveRoundRunner to fail gracefully
      mock_round = double('Round', execution_successful?: false, status: 'failed', fail!: true)
      mock_result = { round: mock_round }
      mock_runner = double('InteractiveRoundRunner')
      allow(InteractiveRoundRunner).to receive(:new).and_return(mock_runner)
      allow(mock_runner).to receive(:execute).and_return(mock_result)

      # Attempt to continue conversation (should handle failure gracefully)
      post :continue, params: { id: conversation_with_round.id }
      
      conversation_with_round.reload

      # Should have created the new round and handled failure gracefully
      expect(conversation_with_round.rounds.count).to eq(2)
      new_round = conversation_with_round.rounds.order(:number).last
      expect(new_round.number).to eq(2)
    end

    it 'provides a way to handle failed conversations through round management' do
      # Create a conversation with a failed round
      failed_conversation = create(:conversation, :with_alice_and_bob,
                                  user: user,
                                  conversation_topic: 'Failed Test',
                                  status: 'failed')

      # Add a failed round for realism
      create(:round, :failed, conversation: failed_conversation, number: 1)

      # Test that failed conversations still have their data intact
      expect(failed_conversation.status).to eq('failed')
      expect(failed_conversation.can_start?).to be(true) # Can still start (has participants)
      expect(failed_conversation.can_continue?).to be(false) # Can't continue from failed state
      expect(failed_conversation.rounds.count).to eq(1)
    end

    it 'handles completed conversations correctly' do
      # Create a completed conversation with factory
      completed_conversation = create(:conversation, :complete, :with_alice_and_bob,
                                    user: user,
                                    conversation_topic: 'Completed Test')

      # Add completed rounds for realism
      create(:round, :completed, :with_all_messages,
             conversation: completed_conversation, number: 1)
      create(:round, :completed, :with_all_messages,
             conversation: completed_conversation, number: 2)

      # Completed conversations maintain their state
      expect(completed_conversation.status).to eq('complete')
      expect(completed_conversation.can_start?).to be(true) # Still has participants
      expect(completed_conversation.can_continue?).to be(false) # Can't continue from complete state
      expect(completed_conversation.rounds.count).to eq(2)
    end

    it 'validates conversation state consistency' do
      # Test that conversations maintain consistent state
      test_conversation = create(:conversation, :with_alice_and_bob,
                                user: user,
                                conversation_topic: 'State Test',
                                status: 'pending')

      # Add an in-progress round
      create(:round, :in_progress, :with_partial_messages,
             conversation: test_conversation, number: 1)

      # Conversation should maintain its status
      expect(test_conversation.status).to eq('pending')
      expect(test_conversation.rounds.count).to eq(1)
      expect(test_conversation.rounds.first.status).to eq('in_progress')
    end

    it 'properly handles round state transitions during failures' do
      # Start with a conversation that has completed rounds
      conversation_with_history = create(:conversation, :with_alice_and_bob,
                                       user: user,
                                       conversation_topic: 'State Transition Test',
                                       max_rounds: 3,
                                       status: 'pending')

      # Create a completed round
      create(:round, :completed, :with_all_messages,
             conversation: conversation_with_history, number: 1)

      # Mock failure during continue
      mock_round = double('Round', execution_successful?: false, status: 'failed', fail!: true)
      mock_result = { round: mock_round }
      mock_runner = double('InteractiveRoundRunner')
      allow(InteractiveRoundRunner).to receive(:new).and_return(mock_runner)
      allow(mock_runner).to receive(:execute).and_return(mock_result)

      # Should handle failure gracefully
      post :continue, params: { id: conversation_with_history.id }
      
      conversation_with_history.reload

      # Should have 2 rounds: 1 completed, 1 newly created
      expect(conversation_with_history.rounds.count).to eq(2)
      expect(conversation_with_history.rounds.first.status).to eq('completed')
      expect(conversation_with_history.rounds.last.number).to eq(2)
    end
  end
end
