# Round-Based Architecture Documentation

## Overview

RoboConvo has been refactored from a monolithic `RoundService` to a clean, layered architecture based on the **Round** model. This new architecture implements the **Single Responsibility Principle**, separating UI concerns, business logic, and data management into distinct, testable components.

## Core Concepts

### 1. Round Model (`app/models/round.rb`)
The **Round** is the central unit of conversation execution, representing one complete cycle where all participants speak once.

```ruby
class Round < ApplicationRecord
  include AASM
  
  belongs_to :conversation
  has_many :messages, dependent: :destroy
  
  # AASM state machine
  aasm column: :status do
    state :pending, initial: true
    state :in_progress, :paused, :completed, :failed, :timed_out
    
    event :start   # pending → in_progress
    event :pause   # in_progress → paused  
    event :resume  # paused → in_progress
    event :complete # in_progress → completed
    event :fail    # [in_progress, paused] → failed
    event :timeout # [in_progress, paused] → timed_out
  end
end
```

**Key Features:**
- **AASM state machine** for reliable state transitions
- **Participant tracking** with `next_participant_index` and efficient `current_participant` method
- **Progress calculation** with `progress_percentage`
- **Convenience methods** like `execution_successful?`, `execution_failed?`, `can_be_resumed?`

### 2. Updated Data Model

```
Conversation
├── has_many :rounds
├── has_many :messages, through: :rounds  
└── has_many :participants

Round  
├── belongs_to :conversation
├── has_many :messages
├── tracks next_participant_index
└── manages AASM state

Message
├── belongs_to :round (NEW)
├── belongs_to :conversation_participant  
└── stores LLM response data
```

**Key Changes:**
- Messages now belong to **Round** instead of directly to Conversation
- Round tracking replaces the old `current_round` integer field
- Clean cascade deletion: `conversation.rounds.destroy_all` removes everything

## Architecture Layers

### 3. Orchestration Layer

#### RoundOrchestrator (`app/services/round_orchestrator.rb`)
The **core business logic engine** that executes rounds with event-driven callbacks.

```ruby
class RoundOrchestrator
  def execute
    round.start! if round.pending?
    
    # Process participants efficiently (one at a time)
    while (participant = round.current_participant)
      success = execute_turn_safely(participant)
      break unless success
      round.advance_participant!
    end
    
    round.complete! if round.all_participants_have_spoken?
    { status: round.status.to_sym, round: round }
  end
  
  # Event system for callbacks
  def on(event_name, &block)
    @callbacks[event_name.to_sym] << block
  end
end
```

**Features:**
- **Event-driven callbacks**: `:round_started`, `:turn_started`, `:turn_completed`, `:round_completed`, `:round_failed`
- **Resumable execution**: Can pause/resume mid-round
- **Error handling**: Automatic failure states with detailed logging
- **Memory safety**: Callback cleanup to prevent memory leaks

#### TurnService (`app/services/turn_service.rb`)
Handles **individual participant responses** with transaction safety.

```ruby
class TurnService
  def execute
    ActiveRecord::Base.transaction do
      message = generate_llm_response
      round.touch(:last_activity_at)
      message
    end
  end
  
  private
  
  def generate_llm_response
    llm_service = LlmService.new(round.conversation, participant)
    message_data = llm_service.generate_response
    
    Message.create!(
      round: round,
      conversation_participant: message_data[:conversation_participant],
      # ... other fields
    )
  end
end
```

**Features:**
- **Security validation**: Ensures participant belongs to conversation
- **Transaction safety**: Atomic message creation and round updates
- **LLM integration**: Delegates to existing `LlmService`

### 4. Execution Strategy Layer

Two execution strategies implement the **Strategy Pattern** to switch between interactive and background modes:

#### InteractiveRoundRunner (`app/services/interactive_round_runner.rb`)
For **real-time UI updates** with Turbo Streams broadcasting.

```ruby
class InteractiveRoundRunner
  def execute
    orchestrator = RoundOrchestrator.new(round)
    broadcaster = create_broadcaster
    setup_event_callbacks(orchestrator, broadcaster)
    orchestrator.execute
  end
  
  private
  
  def setup_event_callbacks(orchestrator, broadcaster)
    orchestrator.on(:round_started) { |payload| broadcaster.round_started(payload) }
    orchestrator.on(:turn_started) { |payload| broadcaster.turn_started(payload) }
    orchestrator.on(:turn_completed) { |payload| broadcaster.turn_completed(payload) }
    # ... more callbacks
  end
end
```

#### BackgroundRoundRunner (`app/services/background_round_runner.rb`) 
For **background job execution** without UI overhead.

```ruby
class BackgroundRoundRunner
  def execute
    orchestrator = RoundOrchestrator.new(round)
    setup_minimal_callbacks(orchestrator)  # Only logging
    orchestrator.execute
  end
end
```

**Benefits:**
- **Performance optimization**: Background mode skips UI broadcasting
- **Same core logic**: Both use identical RoundOrchestrator
- **Easy switching**: Change execution strategy without touching business logic

### 5. UI Broadcasting Layer

#### ConversationBroadcaster (`app/services/conversation_broadcaster.rb`)
Extracted from old RoundService, handles **Turbo Streams** for real-time UI updates.

```ruby
class ConversationBroadcaster
  def round_started(payload)
    broadcast_update("round-#{payload[:round].id}", 'round_progress', {
      round: payload[:round],
      status: 'In Progress'
    })
  end
  
  def turn_completed(payload)
    broadcast_update("conversation-#{payload[:round].conversation.id}", 'messages', {
      conversation: payload[:round].conversation
    })
  end
end
```

## Controller Integration

The controller layer is dramatically simplified:

```ruby
class ConversationsController < ApplicationController
  def start
    round = @conversation.rounds.create!(number: 1)
    result = InteractiveRoundRunner.new(round).execute
    
    if round.execution_successful?
      redirect_to @conversation, notice: 'Conversation started!'
    else
      # Handle failure
    end
  end
  
  def continue
    next_round_number = @conversation.current_round_number + 1
    round = @conversation.rounds.create!(number: next_round_number)
    result = InteractiveRoundRunner.new(round).execute
    # ...
  end
end
```

## Key Benefits

### 1. **Single Responsibility Principle**
- **Round**: Data model and state management
- **RoundOrchestrator**: Business logic execution  
- **TurnService**: Individual participant responses
- **Runner classes**: Execution strategy (interactive vs background)
- **ConversationBroadcaster**: UI updates

### 2. **Testability**
- Each component can be tested in isolation
- Mock-friendly interfaces with clear boundaries
- Event-driven callbacks enable behavior verification

### 3. **Performance & Security**
- **N+1 query elimination**: Efficient `current_participant` method
- **Memory leak prevention**: Callback cleanup in `ensure` blocks
- **Security validation**: Participant ownership verification
- **Transaction safety**: Atomic operations with proper rollback

### 4. **Maintainability**
- **Clear separation of concerns**: UI, business logic, and data
- **Strategy pattern**: Easy to add new execution modes
- **Event-driven**: Loosely coupled components
- **Convenience methods**: No magic string comparisons

### 5. **Scalability Preparation**  
- **Rails.events ready**: Event system prepared for Rails 8+ integration
- **Background job ready**: BackgroundRoundRunner for async processing
- **Pause/resume support**: Built-in for long-running conversations

## Migration Strategy

The architecture transition maintains backward compatibility:

1. **Data layer**: Messages now belong to Round, but conversation association preserved via `through: :rounds`
2. **Controller layer**: Updated to use Round creation and execution strategies  
3. **UI layer**: Existing Turbo Streams work unchanged via ConversationBroadcaster
4. **API layer**: Debug endpoint enhanced with Round information

## Usage Examples

### Creating and Executing a Round
```ruby
# Create round
round = conversation.rounds.create!(number: 1)

# Interactive execution (with UI updates)
result = InteractiveRoundRunner.new(round).execute
if round.execution_successful?
  # Success handling
end

# Background execution (for jobs)
result = BackgroundRoundRunner.new(round).execute
```

### Checking Round Status
```ruby
round.execution_successful?  # completed?
round.execution_failed?     # failed? || timed_out?
round.can_be_resumed?       # paused?
round.progress_percentage   # 0-100%
round.current_participant   # Next speaker
```

### Event Handling
```ruby
orchestrator = RoundOrchestrator.new(round)
orchestrator.on(:turn_started) do |payload|
  puts "#{payload[:participant].name} is speaking..."
end
orchestrator.execute
```

This architecture provides a solid foundation for scaling RoboConvo while maintaining clean, testable, and maintainable code.