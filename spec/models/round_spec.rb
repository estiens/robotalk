# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Round, type: :model do
  let(:conversation) { create(:conversation, :with_participants, participants_count: 2) }
  let(:round) { create(:round, conversation: conversation) }

  describe 'associations' do
    it { should belong_to(:conversation) }
    it { should have_many(:messages).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:number) }
    it { should validate_presence_of(:status) }
  end

  describe 'AASM states' do
    it 'starts with pending status' do
      new_round = build(:round)
      expect(new_round.status).to eq('pending')
      expect(new_round.pending?).to be true
    end

    describe 'state transitions' do
      context 'from pending' do
        it 'can transition to in_progress' do
          expect { round.start! }.to change(round, :status).from('pending').to('in_progress')
        end

        it 'cannot transition directly to completed' do
          expect { round.complete! }.to raise_error(AASM::InvalidTransition)
        end

        it 'cannot transition directly to paused' do
          expect { round.pause!('test') }.to raise_error(AASM::InvalidTransition)
        end
      end

      context 'from in_progress' do
        let(:in_progress_round) { create(:round, :in_progress, conversation: conversation) }

        it 'can transition to paused' do
          expect { in_progress_round.pause!('Rate limit hit') }
            .to change(in_progress_round, :status).from('in_progress').to('paused')
        end

        it 'can transition to completed' do
          expect { in_progress_round.complete! }
            .to change(in_progress_round, :status).from('in_progress').to('completed')
        end

        it 'can transition to failed' do
          expect { in_progress_round.fail!('API error') }
            .to change(in_progress_round, :status).from('in_progress').to('failed')
        end

        it 'can transition to timed_out' do
          expect { in_progress_round.timeout! }
            .to change(in_progress_round, :status).from('in_progress').to('timed_out')
        end
      end

      context 'from paused' do
        let(:paused_round) { create(:round, :paused, conversation: conversation) }

        it 'can resume to in_progress' do
          expect { paused_round.resume! }
            .to change(paused_round, :status).from('paused').to('in_progress')
        end

        it 'can transition to failed' do
          expect { paused_round.fail!('Unrecoverable error') }
            .to change(paused_round, :status).from('paused').to('failed')
        end
      end
    end

    describe 'transition callbacks' do
      it 'sets started_at when starting' do
        freeze_time do
          expect { round.start! }
            .to change(round, :started_at).from(nil).to(be_within(1.second).of(Time.current))
        end
      end

      it 'updates last_activity_at when starting' do
        freeze_time do
          expect { round.start! }
            .to change(round, :last_activity_at).from(nil).to(be_within(1.second).of(Time.current))
        end
      end

      it 'sets completed_at when completing' do
        in_progress_round = create(:round, :in_progress, conversation: conversation)
        freeze_time do
          expect { in_progress_round.complete! }
            .to change(in_progress_round, :completed_at).from(nil).to(be_within(1.second).of(Time.current))
        end
      end

      it 'sets pause_reason when pausing' do
        in_progress_round = create(:round, :in_progress, conversation: conversation)
        expect { in_progress_round.pause!('Rate limit exceeded') }
          .to change(in_progress_round, :pause_reason).from(nil).to('Rate limit exceeded')
      end

      it 'sets failure_reason when failing' do
        in_progress_round = create(:round, :in_progress, conversation: conversation)
        expect { in_progress_round.fail!('API error occurred') }
          .to change(in_progress_round, :failure_reason).from(nil).to('API error occurred')
      end
    end
  end

  describe '#participants_to_process' do
    let!(:participant1) { conversation.participants.ordered.first }
    let!(:participant2) { conversation.participants.ordered.second }

    it 'returns all participants when next_participant_index is 0' do
      round.update!(next_participant_index: 0)
      expect(round.participants_to_process).to match_array([participant1, participant2])
    end

    it 'returns remaining participants when next_participant_index is 1' do
      round.update!(next_participant_index: 1)
      expect(round.participants_to_process).to match_array([participant2])
    end

    it 'returns empty array when all participants processed' do
      round.update!(next_participant_index: 2)
      expect(round.participants_to_process).to be_empty
    end
  end

  describe '#advance_participant!' do
    it 'increments next_participant_index' do
      expect { round.advance_participant! }
        .to change(round, :next_participant_index).from(0).to(1)
    end

    it 'updates last_activity_at' do
      freeze_time do
        expect { round.advance_participant! }
          .to change(round, :last_activity_at).to(be_within(1.second).of(Time.current))
      end
    end
  end

  describe '#all_participants_have_spoken?' do
    it 'returns false when not all participants have spoken' do
      round.update!(next_participant_index: 1)
      expect(round.all_participants_have_spoken?).to be false
    end

    it 'returns true when all participants have spoken' do
      round.update!(next_participant_index: 2)
      expect(round.all_participants_have_spoken?).to be true
    end
  end

  describe '#progress_percentage' do
    it 'returns 0 when no participants have spoken' do
      round.update!(next_participant_index: 0)
      expect(round.progress_percentage).to eq(0)
    end

    it 'returns 50 when half have spoken' do
      round.update!(next_participant_index: 1)
      expect(round.progress_percentage).to eq(50)
    end

    it 'returns 100 when all have spoken' do
      round.update!(next_participant_index: 2)
      expect(round.progress_percentage).to eq(100)
    end

    it 'handles single participant conversation' do
      single_participant_conversation = create(:conversation, :with_participants, participants_count: 1)
      single_round = create(:round, conversation: single_participant_conversation)
      
      single_round.update!(next_participant_index: 0)
      expect(single_round.progress_percentage).to eq(0)
      
      single_round.update!(next_participant_index: 1)
      expect(single_round.progress_percentage).to eq(100)
    end
  end

  describe '#duration' do
    it 'returns nil when not started' do
      expect(round.duration).to be_nil
    end

    it 'returns duration from start to completion' do
      start_time = 1.hour.ago
      end_time = 30.minutes.ago
      
      round.update!(
        started_at: start_time,
        completed_at: end_time
      )
      
      expect(round.duration).to be_within(1.second).of(30.minutes)
    end

    it 'returns duration from start to now when in progress' do
      start_time = 1.hour.ago
      round.update!(started_at: start_time)
      
      freeze_time do
        expect(round.duration).to be_within(1.second).of(1.hour)
      end
    end

    it 'returns duration from start to failed_at when failed' do
      start_time = 2.hours.ago
      failed_time = 1.hour.ago
      
      round.update!(
        started_at: start_time,
        failed_at: failed_time
      )
      
      expect(round.duration).to be_within(1.second).of(1.hour)
    end
  end
end
