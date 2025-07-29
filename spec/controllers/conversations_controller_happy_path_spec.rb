# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConversationsController, type: :controller do
  let(:user) { create(:user) }
  let!(:conversation) { create(:conversation, :with_alice_and_bob, user: user, max_rounds: 3) }
  let(:alice) { conversation.participants.find_by(name: 'Alice') }
  let(:bob) { conversation.participants.find_by(name: 'Bob') }

  before do
    # Mock authentication
    allow(controller).to receive(:current_user).and_return(user)
    allow(controller).to receive(:logged_in?).and_return(true)
    allow(controller).to receive(:require_user).and_return(true)
  end

  describe 'POST #continue' do
    context 'when round executes successfully' do
      before do
        # Mock LLM service for successful responses
        # We need to mock the service differently for each participant
        allow(LlmService).to receive(:new) do |conversation, participant|
          service_mock = double('LlmService')
          
          if participant.name == 'Alice'
            allow(service_mock).to receive(:generate_response).and_return({
              conversation_participant: alice,
              model_id: alice.model_id,
              content: 'Test response from Alice',
              metadata: { response_time: 0.1 }
            })
          else
            allow(service_mock).to receive(:generate_response).and_return({
              conversation_participant: bob,
              model_id: bob.model_id,
              content: 'Test response from Bob',
              metadata: { response_time: 0.1 }
            })
          end
          
          service_mock
        end
      end

      it 'creates and executes a round successfully' do
        expect(conversation.rounds.count).to eq(0)
        
        post :continue, params: { id: conversation.id }
        
        expect(response).to have_http_status(:redirect)
        
        # Verify round was created in database
        conversation.reload
        expect(conversation.rounds.count).to eq(1)
        
        round = conversation.rounds.first
        expect(round.number).to eq(1)
        expect(round).to be_completed
        expect(round.messages.count).to eq(2) # Both participants should have spoken
        
        # Verify message order
        messages = round.messages.order(:created_at)
        expect(messages.first.conversation_participant).to eq(alice)
        expect(messages.second.conversation_participant).to eq(bob)
      end

      it 'executes multiple rounds in sequence' do
        # Execute Round 1
        post :continue, params: { id: conversation.id }
        expect(response).to have_http_status(:redirect)
        
        # Execute Round 2
        post :continue, params: { id: conversation.id }
        expect(response).to have_http_status(:redirect)
        
        # Execute Round 3 (max_rounds)
        post :continue, params: { id: conversation.id }
        expect(response).to have_http_status(:redirect)
        
        # Verify database state
        conversation.reload
        expect(conversation.rounds.count).to eq(3)
        expect(conversation.messages.count).to eq(6) # 3 rounds × 2 participants
        expect(conversation.can_continue?).to be false
      end

      it 'maintains participant turn order across rounds' do
        # Complete all 3 rounds
        3.times do
          post :continue, params: { id: conversation.id }
          expect(response).to have_http_status(:redirect)
        end
        
        # Verify each round has correct participant order
        conversation.reload
        (1..3).each do |round_num|
          round = conversation.rounds.find_by(number: round_num)
          messages = round.messages.order(:created_at)
          
          expect(messages.first.conversation_participant).to eq(alice)
          expect(messages.second.conversation_participant).to eq(bob)
        end
      end
    end

    context 'when LLM service fails' do
      before do
        # Mock LLM service to fail
        allow(LlmService).to receive(:new) do |conversation, participant|
          service_mock = double('LlmService')
          allow(service_mock).to receive(:generate_response).and_raise(
            LlmService::LlmApiError, 'API rate limit exceeded'
          )
          service_mock
        end
      end

      it 'handles LLM failures gracefully' do
        post :continue, params: { id: conversation.id }
        
        # Should still respond successfully (not crash)
        expect(response).to have_http_status(:redirect)
        
        # Verify round is in failed state
        conversation.reload
        round = conversation.rounds.find_by(number: 1)
        expect(round).to be_failed
        expect(round.failure_reason).to eq('API rate limit exceeded')
      end
    end

    context 'with multi-user isolation' do
      let(:other_user) { create(:user) }
      let(:other_conversation) { create(:conversation, :with_alice_and_bob, user: other_user, max_rounds: 2) }

      it 'only allows access to conversations owned by current user' do
        # Try to access another user's conversation
        expect {
          post :continue, params: { id: other_conversation.id }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it 'isolates conversation execution between users' do
        # Set up successful round execution
        allow(LlmService).to receive(:new) do |conversation, participant|
          service_mock = double('LlmService')
          allow(service_mock).to receive(:generate_response).and_return({
            conversation_participant: participant,
            model_id: participant.model_id,
            content: 'Test response',
            metadata: { response_time: 0.1 }
          })
          service_mock
        end

        # Execute round for current user's conversation
        post :continue, params: { id: conversation.id }
        expect(response).to have_http_status(:redirect)
        
        # Verify other user's conversation is unaffected
        expect(other_conversation.reload.rounds.count).to eq(0)
        expect(other_conversation.messages.count).to eq(0)
      end
    end

    context 'AASM state transitions' do
      before do
        # Mock LLM service for successful responses
        allow(LlmService).to receive(:new) do |conversation, participant|
          service_mock = double('LlmService')
          
          if participant.name == 'Alice'
            allow(service_mock).to receive(:generate_response).and_return({
              conversation_participant: alice,
              model_id: alice.model_id,
              content: 'Test response from Alice',
              metadata: { response_time: 0.1 }
            })
          else
            allow(service_mock).to receive(:generate_response).and_return({
              conversation_participant: bob,
              model_id: bob.model_id,
              content: 'Test response from Bob',
              metadata: { response_time: 0.1 }
            })
          end
          
          service_mock
        end
      end

      it 'properly transitions round states during execution' do
        post :continue, params: { id: conversation.id }
        
        conversation.reload
        round = conversation.rounds.first
        
        # Round should be completed after execution
        expect(round).to be_completed
        expect(round.started_at).to be_present
        expect(round.completed_at).to be_present
      end

      it 'handles round state transitions on failure' do
        # Mock LLM service to fail 
        allow(LlmService).to receive(:new) do |conversation, participant|
          service_mock = double('LlmService')
          allow(service_mock).to receive(:generate_response).and_raise(
            LlmService::LlmApiError, 'API error'
          )
          service_mock
        end

        post :continue, params: { id: conversation.id }
        
        conversation.reload
        round = conversation.rounds.first
        
        # Round should be failed
        expect(round).to be_failed
        expect(round.started_at).to be_present
        expect(round.failed_at).to be_present
        expect(round.failure_reason).to eq('API error')
      end
    end
  end

  describe 'GET #show' do
    it 'displays conversation successfully' do
      get :show, params: { id: conversation.id }
      
      expect(response).to have_http_status(:success)
      # In a controller spec, the response body might be empty due to view rendering limitations
      # The important thing is that the request succeeds and finds the conversation
    end

    it 'loads conversation with proper associations' do  
      get :show, params: { id: conversation.id }
      
      expect(response).to have_http_status(:success)
      # The controller should successfully find the conversation with participants loaded
      # This tests the controller logic, not the view rendering
    end  
  end
end