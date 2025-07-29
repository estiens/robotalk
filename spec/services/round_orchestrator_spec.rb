# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RoundOrchestrator, type: :service do
  let(:conversation) { create(:conversation, :with_participants, participants_count: 2) }
  let(:round) { create(:round, conversation: conversation) }
  let(:orchestrator) { described_class.new(round) }
  let(:participant1) { conversation.participants.ordered.first }
  let(:participant2) { conversation.participants.ordered.second }

  describe '#initialize' do
    it 'sets up the round and callback hash' do
      expect(orchestrator.round).to eq(round)
      expect(orchestrator.logger).to eq(Rails.logger)
    end
  end

  describe '#on' do
    it 'registers a callback for an event' do
      callback_spy = spy('callback')
      
      orchestrator.on(:test_event) { |payload| callback_spy.call(payload) }
      orchestrator.send(:notify, :test_event, { test: 'data' })
      
      expect(callback_spy).to have_received(:call).with({ test: 'data' })
    end

    it 'allows multiple callbacks for the same event' do
      callback1 = spy('callback1')
      callback2 = spy('callback2')
      
      orchestrator.on(:test_event) { |payload| callback1.call(payload) }
      orchestrator.on(:test_event) { |payload| callback2.call(payload) }
      
      orchestrator.send(:notify, :test_event, { test: 'data' })
      
      expect(callback1).to have_received(:call).with({ test: 'data' })
      expect(callback2).to have_received(:call).with({ test: 'data' })
    end

    it 'returns self for chaining' do
      result = orchestrator.on(:test_event) { |payload| }
      expect(result).to eq(orchestrator)
    end
  end

  describe '#execute' do
    let(:turn_service_double) { instance_double(TurnService) }
    let(:message_double) { instance_double(Message, content: 'Test response') }
    
    before do
      allow(TurnService).to receive(:new).and_return(turn_service_double)
      allow(turn_service_double).to receive(:execute).and_return(message_double)
    end

    context 'with a pending round' do
      it 'starts the round and fires round_started event' do
        listener = spy('event_listener')
        orchestrator.on(:round_started) { |payload| listener.round_started(payload) }
        orchestrator.on(:round_completed) { |payload| listener.round_completed(payload) }
        
        expect(round.pending?).to be true  # Ensure round starts as pending
        
        orchestrator.execute
        
        # Round should be completed after processing all participants
        expect(round.reload.completed?).to be true
        expect(listener).to have_received(:round_started).with(
          a_hash_including(
            round: round,
            conversation: conversation,
            total_participants: 2
          )
        )
        expect(listener).to have_received(:round_completed)
      end
    end

    context 'with an in_progress round' do
      let(:round) { create(:round, :in_progress, conversation: conversation) }

      it 'processes each participant in order' do
        listener = spy('event_listener')
        orchestrator.on(:turn_started) { |payload| listener.turn_started(payload) }
        orchestrator.on(:turn_completed) { |payload| listener.turn_completed(payload) }
        
        orchestrator.execute
        
        expect(TurnService).to have_received(:new).with(round, participant1)
        expect(TurnService).to have_received(:new).with(round, participant2)
        expect(turn_service_double).to have_received(:execute).twice
        
        expect(listener).to have_received(:turn_started).twice
        expect(listener).to have_received(:turn_completed).twice
      end

      it 'fires turn events with correct data' do
        listener = spy('event_listener')
        orchestrator.on(:turn_started) { |payload| listener.turn_started(payload) }
        orchestrator.on(:turn_completed) { |payload| listener.turn_completed(payload) }
        
        orchestrator.execute
        
        expect(listener).to have_received(:turn_started).with(
          a_hash_including(
            round: round,
            participant: participant1,
            progress: kind_of(Numeric)
          )
        )
        expect(listener).to have_received(:turn_completed).with(
          a_hash_including(
            round: round,
            participant: participant1,
            result: message_double,
            progress: kind_of(Numeric)
          )
        )
      end

      it 'advances participants and completes the round' do
        orchestrator.execute
        
        expect(round.reload).to be_completed
        expect(round.next_participant_index).to eq(2)
      end

      it 'fires round.completed event when all participants finish' do
        listener = spy('event_listener')
        orchestrator.on(:round_completed) { |payload| listener.round_completed(payload) }
        
        orchestrator.execute
        
        expect(listener).to have_received(:round_completed).with(
          a_hash_including(
            round: round,
            conversation: conversation
          )
        )
      end
    end

    context 'when TurnService raises a rate limit error' do
      let(:round) { create(:round, :in_progress, conversation: conversation) }
      let(:rate_limit_error) { Class.new(LlmService::LlmApiError) }
      
      before do
        stub_const('LlmService::RateLimitError', rate_limit_error)
        allow(turn_service_double).to receive(:execute)
          .and_raise(rate_limit_error.new('Rate limit exceeded'))
      end

      it 'fails the round and fires round.failed event' do
        listener = spy('event_listener')
        orchestrator.on(:round_failed) { |payload| listener.round_failed(payload) }
        
        orchestrator.execute
        
        # Don't reload - check in-memory state since RSpec rolls back transactions
        expect(round).to be_failed
        expect(round.failure_reason).to eq('Rate limit exceeded')
        expect(listener).to have_received(:round_failed).with(
          a_hash_including(
            round: round,
            error: kind_of(rate_limit_error),
            reason: 'Rate limit exceeded'
          )
        )
      end

      it 'stops processing subsequent participants' do
        orchestrator.execute
        
        expect(TurnService).to have_received(:new).once.with(round, participant1)
        expect(TurnService).not_to have_received(:new).with(round, participant2)
      end
    end

    context 'when TurnService raises a generic error' do
      let(:round) { create(:round, :in_progress, conversation: conversation) }
      
      before do
        allow(turn_service_double).to receive(:execute)
          .and_raise(StandardError.new('API timeout'))
      end

      it 'fails the round and fires round.failed event' do
        listener = spy('event_listener')
        orchestrator.on(:round_failed) { |payload| listener.round_failed(payload) }
        
        expect { orchestrator.execute }.to raise_error(StandardError, 'API timeout')
        
        # Don't reload - check in-memory state since RSpec rolls back transactions
        expect(round).to be_failed
        expect(round.failure_reason).to eq('API timeout')
        expect(listener).to have_received(:round_failed).with(
          a_hash_including(
            round: round,
            error: kind_of(StandardError),
            reason: 'API timeout'
          )
        )
      end

      it 'stops processing and re-raises the error' do
        expect { orchestrator.execute }.to raise_error(StandardError, 'API timeout')
        
        expect(TurnService).to have_received(:new).once.with(round, participant1)
        expect(TurnService).not_to have_received(:new).with(round, participant2)
      end
    end

    context 'when callback raises an error' do
      let(:round) { create(:round, :in_progress, conversation: conversation) }
      
      it 'logs the error but continues execution' do
        allow(Rails.logger).to receive(:error)
        
        orchestrator.on(:turn_started) { |payload| raise 'Callback failed' }
        
        expect { orchestrator.execute }.not_to raise_error
        
        # Expect error log for each participant (2 participants)
        expect(Rails.logger).to have_received(:error)
          .with(match(/Event callback error for 'turn_started': Callback failed/)).twice
        expect(round).to be_completed
      end
    end
  end

  describe 'resumability' do
    context 'with a partially completed round' do
      let(:round) { create(:round, :in_progress, conversation: conversation, next_participant_index: 1) }
      let(:turn_service_double) { instance_double(TurnService) }
      let(:message_double) { instance_double(Message, content: 'Test response') }
      
      before do
        allow(TurnService).to receive(:new).and_return(turn_service_double)
        allow(turn_service_double).to receive(:execute).and_return(message_double)
      end

      it 'resumes from the correct participant' do
        orchestrator.execute
        
        expect(TurnService).to have_received(:new).once.with(round, participant2)
        expect(TurnService).not_to have_received(:new).with(round, participant1)
      end

      it 'completes the round after processing remaining participants' do
        orchestrator.execute
        
        expect(round.reload).to be_completed
        expect(round.next_participant_index).to eq(2)
      end
    end

    context 'with a paused round' do
      let(:round) { create(:round, :paused, conversation: conversation, next_participant_index: 1) }
      let(:turn_service_double) { instance_double(TurnService) }
      let(:message_double) { instance_double(Message, content: 'Test response') }
      
      before do
        allow(TurnService).to receive(:new).and_return(turn_service_double)
        allow(turn_service_double).to receive(:execute).and_return(message_double)
      end

      it 'resumes the round and continues from where it left off' do
        listener = spy('event_listener')
        orchestrator.on(:round_started) { |payload| listener.round_started(payload) }
        
        orchestrator.execute
        
        # After executing the remaining participant, round should be completed
        expect(round).to be_completed
        expect(TurnService).to have_received(:new).once.with(round, participant2)
        expect(listener).to have_received(:round_started)
      end
    end
  end
end