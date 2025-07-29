# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BackgroundRoundRunner do
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

    it 'initializes with background-appropriate defaults' do
      runner = described_class.new(round)
      expect(runner.broadcast_enabled?).to be false
      expect(runner.log_progress?).to be true
    end

    it 'accepts custom options' do
      runner = described_class.new(round, log_progress: false)
      expect(runner.log_progress?).to be false
    end
  end

  describe '#execute' do
    let(:orchestrator) { instance_double(RoundOrchestrator) }

    before do
      allow(RoundOrchestrator).to receive(:new).and_return(orchestrator)
      allow(orchestrator).to receive(:on).and_return(orchestrator)
    end

    context 'successful execution' do
      before do
        allow(orchestrator).to receive(:execute).and_return({ status: :completed, round: round })
      end

      it 'creates orchestrator with minimal callbacks' do
        expect(RoundOrchestrator).to receive(:new).with(round)
        expect(orchestrator).to receive(:on).with(:round_started)
        expect(orchestrator).to receive(:on).with(:round_completed)
        expect(orchestrator).to receive(:on).with(:round_failed)
        
        # Should NOT set up turn-level callbacks for background execution
        expect(orchestrator).not_to receive(:on).with(:turn_started)
        expect(orchestrator).not_to receive(:on).with(:turn_completed)
        
        runner.execute
      end

      it 'does not instantiate broadcaster' do
        expect(ConversationBroadcaster).not_to receive(:new)
        
        runner.execute
      end

      it 'logs progress events when enabled' do
        expect(Rails.logger).to receive(:info)
          .with(/Background round started: #{round.id}/)
        expect(Rails.logger).to receive(:info)
          .with(/Background round completed: #{round.id}/)
        
        # Set up callback capture
        @callbacks = {}
        allow(orchestrator).to receive(:on) do |event, &block|
          @callbacks[event] = block
          orchestrator
        end
        
        # Set up the orchestrator to trigger our callbacks
        allow(orchestrator).to receive(:execute) do
          # Trigger the callbacks that were registered
          @callbacks[:round_started]&.call({ round: round })
          @callbacks[:round_completed]&.call({ round: round })
          
          { status: :completed }
        end
        
        runner.execute
      end

      it 'skips logging when disabled' do
        runner = described_class.new(round, log_progress: false)
        
        expect(Rails.logger).not_to receive(:info)
        
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

        runner.execute
        
        expect(runner.execution_time).to be_between(0.04, 0.1)
      end
    end

    context 'error handling' do
      let(:error) { StandardError.new('Background processing failed') }

      before do
        allow(orchestrator).to receive(:execute).and_raise(error)
      end

      it 'logs errors' do
        expect(Rails.logger).to receive(:error)
          .with(/Background round error: #{round.id}/)
        expect(Rails.logger).to receive(:error)
          .with(/#{error.message}/)
        
        expect { runner.execute }.to raise_error(error)
      end

      it 'propagates the error' do
        expect { runner.execute }.to raise_error(error)
      end
    end

    context 'performance characteristics' do
      it 'executes without UI overhead' do
        # Verify no ConversationBroadcaster is created (the main source of overhead)
        expect(ConversationBroadcaster).not_to receive(:new)
        
        # Verify minimal callback setup (less overhead than interactive mode)
        expect(orchestrator).to receive(:on).exactly(3).times  # Only core callbacks
        expect(orchestrator).to receive(:execute).and_return({ status: :completed })
        
        runner.execute
      end

      it 'logs slow executions' do
        allow(orchestrator).to receive(:execute) do
          sleep 2.1
          { status: :completed }
        end

        expect(Rails.logger).to receive(:warn)
          .with(/Long-running background round: #{round.id} took \d+\.\d+s/)
        
        runner.execute
      end
    end
  end

  describe '#broadcast_enabled?' do
    it 'returns false by default' do
      expect(runner.broadcast_enabled?).to be false
    end

    it 'cannot be enabled for background runner' do
      runner = described_class.new(round, broadcast: true)
      expect(runner.broadcast_enabled?).to be false
    end
  end

  describe '#log_progress?' do
    it 'returns true by default' do
      expect(runner.log_progress?).to be true
    end

    it 'can be disabled via options' do
      runner = described_class.new(round, log_progress: false)
      expect(runner.log_progress?).to be false
    end
  end

  describe 'comparison with InteractiveRoundRunner' do
    let(:interactive_runner) { InteractiveRoundRunner.new(round) }
    let(:background_runner) { described_class.new(round) }
    let(:orchestrator) { instance_double(RoundOrchestrator) }

    before do
      allow(RoundOrchestrator).to receive(:new).and_return(orchestrator)
      allow(orchestrator).to receive(:on).and_return(orchestrator)
      allow(orchestrator).to receive(:execute).and_return({ status: :completed })
    end

    it 'uses same orchestrator but different callback configuration' do
      interactive_callbacks = []
      background_callbacks = []
      
      # Test interactive runner first
      interactive_orchestrator = instance_double(RoundOrchestrator)
      allow(RoundOrchestrator).to receive(:new).and_return(interactive_orchestrator)
      allow(interactive_orchestrator).to receive(:on) do |event, &block|
        interactive_callbacks << event
        interactive_orchestrator
      end
      allow(interactive_orchestrator).to receive(:execute).and_return({ status: :completed })
      allow(ConversationBroadcaster).to receive(:new).and_return(instance_double(ConversationBroadcaster))
      
      interactive_runner.execute
      
      # Test background runner second
      background_orchestrator = instance_double(RoundOrchestrator)  
      allow(RoundOrchestrator).to receive(:new).and_return(background_orchestrator)
      allow(background_orchestrator).to receive(:on) do |event, &block|
        background_callbacks << event
        background_orchestrator
      end
      allow(background_orchestrator).to receive(:execute).and_return({ status: :completed })
      
      background_runner.execute
      
      # Interactive has more callbacks
      expect(interactive_callbacks).to include(:turn_started, :turn_completed)
      expect(background_callbacks).not_to include(:turn_started, :turn_completed)
      
      # Both have core callbacks
      common_callbacks = [:round_started, :round_completed, :round_failed]
      expect(interactive_callbacks).to include(*common_callbacks)
      expect(background_callbacks).to include(*common_callbacks)
    end
  end
end