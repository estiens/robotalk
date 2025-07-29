# RoundService Refactoring Plan

## Overview

This document outlines the complete refactoring of RoboConvo's conversation/round system to address architectural issues and improve maintainability.

## Current Problems

- **RoundService violates SRP**: Mixes business logic, UI broadcasting, state management, and timing
- **No Round entity**: Rounds are just a counter on Conversation, missing important domain concept
- **State management fragmentation**: Scattered across models, services, and controllers
- **UI concerns in domain layer**: Turbo Stream logic embedded in services
- **Tight coupling**: Interactive vs background modes tightly coupled throughout
- **Testing difficulties**: Can't test business logic without UI infrastructure

## New Architecture

### Core Principles
1. **Round as First-Class Entity** - Encapsulates turn management and completion logic
2. **Clear Layer Separation** - Domain, Service, and Presentation layers with defined boundaries
3. **Strategy Pattern for Execution** - Different runners for different contexts
4. **Event-Ready Design** - Callback system that mirrors future Rails.events API
5. **Incremental Migration** - Since app isn't in production, prioritize speed over backwards compatibility

## Domain Models

### Round Model (New)
```ruby
class Round < ApplicationRecord
  include AASM
  
  belongs_to :conversation
  has_many :messages, dependent: :destroy
  
  # Fields:
  # - number: integer (1, 2, 3...)
  # - status: string (AASM managed)
  # - next_participant_index: integer (for resumability)
  # - paused_reason: string
  # - failed_reason: string
  # - last_activity_at: datetime
  
  aasm column: :status do
    state :pending, initial: true
    state :in_progress
    state :paused
    state :completed  
    state :failed
    state :timed_out
    
    # Transitions with guards and callbacks
  end
  
  def participants_to_process
    conversation.participants.ordered.offset(next_participant_index)
  end
  
  def all_participants_have_spoken?
    next_participant_index >= conversation.participants.count
  end
end
```

### Updated Conversation Model
```ruby
class Conversation < ApplicationRecord
  has_many :rounds, dependent: :destroy
  has_many :messages, through: :rounds  # Changed relationship
  
  # Remove round_ready state - not needed with Round model
  enum status: { 
    pending: 'pending',
    active: 'active',      # Renamed from in_progress
    complete: 'complete',
    failed: 'failed'
    # Remove: generating, round_ready
  }
  
  def current_round
    rounds.order(:number).last
  end
  
  def can_continue?
    active? && (current_round.nil? || current_round.completed?) && rounds.count < max_rounds
  end
end
```

### Updated Message Model
```ruby
class Message < ApplicationRecord
  belongs_to :round                    # Changed from conversation
  belongs_to :conversation_participant
  
  delegate :conversation, to: :round
  
  # Remove round_number field - use round.number instead
end
```

## Service Layer

### RoundOrchestrator (Pure Business Logic)
```ruby
class RoundOrchestrator
  def initialize(round)
    @round = round
    @callbacks = Hash.new { |h, k| h[k] = [] }
  end
  
  def on(event_name, &block)
    @callbacks[event_name.to_sym] << block
    self
  end
  
  def execute
    # Resumable execution with event publishing
    # Pure domain logic, no UI knowledge
  end
  
  private
  
  def notify(event_name, payload)
    @callbacks[event_name.to_sym].each { |cb| cb.call(payload) }
  rescue => e
    Rails.logger.error "Event callback error: #{e.message}"
  end
end
```

### TurnService (Individual Responses)
```ruby
class TurnService
  def initialize(round, participant)
    @round = round
    @participant = participant
  end
  
  def execute
    ActiveRecord::Base.transaction do
      message = create_message_from_llm
      @round.touch(:last_activity_at)
      message
    end
  end
end
```

### ConversationFlow (High-Level Coordination)
```ruby
class ConversationFlow
  def advance(conversation)
    conversation.with_lock do
      conversation.reload
      
      return unless conversation.can_continue?
      
      next_round = conversation.rounds.create!(
        number: conversation.rounds.maximum(:number).to_i + 1,
        status: :pending
      )
    end
    
    execute_round(next_round) if next_round
  end
end
```

## Execution Strategies

### InteractiveRoundRunner
```ruby
class InteractiveRoundRunner
  def execute(round)
    orchestrator = RoundOrchestrator.new(round)
    broadcaster = ConversationBroadcaster.new
    
    # Wire up UI callbacks
    orchestrator
      .on('turn.started') { |payload| broadcaster.show_loading(payload) }
      .on('turn.completed') { |payload| broadcaster.announce_turn(payload) }
      .on('round.paused') { |payload| broadcaster.show_paused(payload) }
      .on('round.completed') { |payload| broadcaster.complete_round(payload) }
    
    orchestrator.execute
  end
end
```

### BackgroundRoundRunner
```ruby
class BackgroundRoundRunner
  def execute(round)
    # No callbacks attached - pure execution
    RoundOrchestrator.new(round).execute
  end
end
```

### AutoContinueRunner
```ruby
class AutoContinueRunner
  def execute_multiple_rounds(conversation, count)
    count.times do
      break unless conversation.reload.can_continue?
      
      ConversationFlow.new.advance(conversation)
      sleep(0.5) # Brief pause between rounds
    end
  end
end
```

## Broadcasting Layer

### ConversationBroadcaster
```ruby
class ConversationBroadcaster
  def show_loading(payload)
    # Extract Turbo Stream logic from RoundService
  end
  
  def announce_turn(payload)
    # Broadcast completed turn
  end
  
  def show_paused(payload)
    # Show pause state
  end
  
  def complete_round(payload)
    # Update UI for completed round
  end
end
```

## Migration Strategy

Since the app isn't in production, we can prioritize speed over backwards compatibility:

### Phase 1: Database Changes
1. Create rounds table with all necessary fields
2. Add round_id to messages table
3. Backfill rounds from existing conversation.current_round data
4. Backfill message.round_id from message.round_number
5. Remove round_number column from messages
6. Remove current_round from conversations

### Phase 2: Service Refactoring
1. Create new service classes alongside existing RoundService
2. Extract ConversationBroadcaster from RoundService
3. Update controllers to use new runners
4. Remove old RoundService completely

### Phase 3: Model Updates
1. Update associations (Message belongs_to Round)
2. Remove TurboStreamable concern from Conversation
3. Add AASM to Round model
4. Update Conversation state enum

## Event System Design

### Current Callback Pattern (Rails.events Ready)
```ruby
# Publishing events (in orchestrator)
notify('turn.completed', { 
  round: @round, 
  participant: participant, 
  result: result 
})

# Subscribing to events (in runner)
orchestrator.on('turn.completed') do |payload|
  broadcaster.announce_turn(payload)
end
```

### Future Rails.events Migration
When Rails 8 is released, migration will be simple:
```ruby
# Change notify() to Rails.events.publish()
Rails.events.publish('turn.completed', { 
  round: @round, 
  participant: participant, 
  result: result 
})

# Change callback wiring
Rails.events.with_subscribers(broadcaster) do
  orchestrator.execute
end
```

## Controller Simplification

### Before
```ruby
def continue
  @conversation.update!(status: :in_progress)
  @conversation.perform_round!
  respond_to do |format|
    format.turbo_stream { head :ok }
  end
end
```

### After
```ruby
def continue
  runner = interactive? ? InteractiveRoundRunner : BackgroundRoundRunner
  
  if @conversation.can_continue?
    ConversationFlow.new.advance(@conversation)
  end
  
  respond_to do |format|
    format.turbo_stream { head :ok }
  end
end
```

## Benefits

1. **Single Responsibility**: Each class has one clear purpose
2. **Testability**: Can test business logic without UI dependencies
3. **Flexibility**: Easy to add new conversation modes and runner types
4. **Maintainability**: Clear boundaries between layers
5. **Future-Ready**: Prepared for Rails.events and complex conversation types
6. **Error Handling**: Proper pause/resume for recoverable errors
7. **Concurrency**: Race condition prevention with database locks

## Implementation Order

1. ✅ **Design Complete** - Architecture and patterns defined
2. **Create Round model** - AASM states, associations, methods
3. **Create migration** - rounds table, backfill data, update messages
4. **Implement RoundOrchestrator** - Pure business logic with callbacks
5. **Create execution strategies** - Interactive, Background, AutoContinue runners
6. **Extract ConversationBroadcaster** - All Turbo Stream logic
7. **Update controllers** - Use new runners instead of RoundService
8. **Remove old code** - Delete RoundService, update associations
9. **Add recovery jobs** - Timeout and resume logic for production

## Future Enhancements Enabled

With this architecture, we can easily add:
- **Round Types**: Timed rounds, vote-based, moderator-controlled
- **Variable Participants**: Different speakers per round
- **Parallel Conversations**: Multiple simultaneous discussions
- **Complex Turn Patterns**: Skip patterns, sub-groups
- **Analytics**: Event-driven metrics and monitoring
- **API Support**: Same business logic, different presentation layer

This refactoring transforms the codebase from tightly coupled services to a flexible, extensible conversation engine ready for future requirements.