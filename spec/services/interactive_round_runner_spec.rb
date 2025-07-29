# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InteractiveRoundRunner do
  let(:conversation) { create(:conversation, :with_participants, participants_count: 2) }
  let(:round) { create(:round, conversation: conversation) }
  let(:runner) { described_class.new(round) }

  describe '#initialize' do
    it 'accepts a round' do
      expect { described_class.new(round) }.not_to raise_error
    end

    it 'validates round is persisted' do
      expect { described_class.new(build(:round)) }
        .to raise_error(ArgumentError, /must be persisted/)
    end

    it 'initializes with default options' do
      runner = described_class.new(round)
      expect(runner.broadcast_enabled?).to be true
      expect(runner.async_broadcast?).to be true
    end

    it 'accepts custom options' do
      runner = described_class.new(round, async_broadcast: false)
      expect(runner.async_broadcast?).to be false
    end
  end

  describe '#execute' do
    let(:orchestrator) { instance_double(RoundOrchestrator) }
    let(:broadcaster) { instance_double(ConversationBroadcaster) }

    before do
      allow(RoundOrchestrator).to receive(:new).and_return(orchestrator)
      allow(ConversationBroadcaster).to receive(:new).and_return(broadcaster)
      allow(orchestrator).to receive(:on).and_return(orchestrator)
    end

    context 'successful execution' do
      before do
        allow(orchestrator).to receive(:execute).and_return({ status: :completed, round: round })
      end

      it 'creates orchestrator and sets up event callbacks' do
        expect(RoundOrchestrator).to receive(:new).with(round)
        expect(orchestrator).to receive(:on).with(:round_started)
        expect(orchestrator).to receive(:on).with(:turn_started)
        expect(orchestrator).to receive(:on).with(:turn_completed)
        expect(orchestrator).to receive(:on).with(:round_completed)
        expect(orchestrator).to receive(:on).with(:round_failed)
        
        runner.execute
      end

      it 'creates broadcaster in interactive mode' do
        expect(ConversationBroadcaster).to receive(:new).with(round.conversation, mode: :interactive)
        
        runner.execute
      end

      it 'returns execution result' do
        result = runner.execute
        
        expect(result[:status]).to eq(:completed)
        expect(result[:round]).to eq(round)
      end

      it 'tracks execution timing' do
        allow(orchestrator).to receive(:execute) do
          sleep 0.05
          { status: :completed }
        end

        start_time = Time.current
        runner.execute
        
        expect(runner.execution_time).to be_between(0.04, 0.1)
      end
    end

    context 'with event callbacks' do
      let(:participant) { conversation.participants.first }
      let(:message) { create(:message, round: round, conversation_participant: participant) }

      before do
        # Create a callbacks hash that will store the registered callbacks
        @callbacks = {}
        
        # Mock the `on` method to capture callbacks
        allow(orchestrator).to receive(:on) do |event, &block|
          @callbacks[event] = block
          orchestrator
        end
        
        # Mock execute to trigger the callbacks after they're registered
        allow(orchestrator).to receive(:execute) do
          # Trigger events after callbacks are set up
          @callbacks[:round_started]&.call({ round: round, conversation: conversation })
          @callbacks[:turn_started]&.call({ round: round, participant: participant })
          @callbacks[:turn_completed]&.call({ round: round, participant: participant, result: message })
          @callbacks[:round_completed]&.call({ round: round, conversation: conversation })
          
          { status: :completed }
        end
      end

      it 'triggers broadcaster methods through callbacks' do
        expect(broadcaster).to receive(:broadcast_participant_started).with(participant)
        expect(broadcaster).to receive(:broadcast_message_created).with(message)
        expect(broadcaster).to receive(:broadcast_round_completed)
        
        runner.execute
      end
    end

    context 'error handling' do
      let(:error) { StandardError.new('Processing failed') }

      before do
        allow(orchestrator).to receive(:execute).and_raise(error)
      end

      it 'propagates the error' do
        expect { runner.execute }.to raise_error(error)
      end

      it 'logs execution errors' do
        expect(Rails.logger).to receive(:error).with(/Interactive round execution failed/)
        
        expect { runner.execute }.to raise_error(error)
      end
    end
  end

  describe '#broadcast_enabled?' do
    it 'returns true by default' do
      expect(runner.broadcast_enabled?).to be true
    end

    it 'can be disabled via options' do
      runner = described_class.new(round, broadcast: false)
      expect(runner.broadcast_enabled?).to be false
    end
  end

  describe '#async_broadcast?' do
    it 'returns true by default' do
      expect(runner.async_broadcast?).to be true
    end

    it 'can be disabled via options' do
      runner = described_class.new(round, async_broadcast: false)
      expect(runner.async_broadcast?).to be false
    end
  end
end