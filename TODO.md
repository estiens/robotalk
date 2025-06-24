# RoboConvo Improvement Plan

## Current State Analysis

### ✅ Strengths
- Recently added `round_number` field to messages provides better tracking
- `ConversationParticipant#has_spoken_in_round?` method enables robust round completion checking
- Well-structured streaming implementation with real-time UI updates
- Comprehensive UX with live/history views and auto-continue functionality

### ⚠️ Issues Identified

#### 1. Round Logic Inconsistencies
**Location:** `app/models/conversation.rb:32-37, 169-203`
- `current_round` uses `ceil(assistant_messages / participants)` but round generation logic assumes different semantics
- `generate_one_round!` has complex round number calculation that may not align with `current_round`

#### 2. Speaker Selection Fragility
**Location:** `app/models/conversation.rb:43-63`
- `next_speaker` relies on `model_id` matching, which can fail if participant data is inconsistent
- No fallback when participant lookup fails

#### 3. Message Round Assignment
**Location:** `app/models/conversation.rb:262-302`
- Complex logic in `persist_new_message` for calculating round numbers
- Potential race conditions in multi-threaded environments

#### 4. UX Round Display Issues
**Location:** `app/views/conversations/_message.html.erb:71-98`
- Multiple complex round number calculations in views
- Inconsistent round numbering between live and history views

## Improvement Plan

### Phase 1: Core Logic Improvements

#### 1.1 Simplify Round Management
**Priority:** High
**Files:** `app/models/conversation.rb`

```ruby
# In Conversation model
def current_round
  return 0 if participants.empty?
  latest_round = messages.where(role: "assistant").maximum(:round_number) || 0
  latest_round
end

def current_round_complete?
  return false if current_round == 0
  participants.all? { |p| p.has_spoken_in_round?(current_round) }
end

def next_round_number
  current_round_complete? ? current_round + 1 : [current_round, 1].max
end
```

#### 1.2 Robust Speaker Selection
**Priority:** High
**Files:** `app/models/conversation.rb`

```ruby
def next_speaker_in_round(round_num = next_round_number)
  participants.ordered.find { |p| !p.has_spoken_in_round?(round_num) }
end

def next_speaker
  next_speaker_in_round || participants.ordered.first
end
```

#### 1.3 Streamlined Message Creation
**Priority:** Medium
**Files:** `app/models/conversation.rb`

```ruby
def create_message_for_participant!(participant, content)
  round_num = next_round_number
  unless participant.has_spoken_in_round?(round_num)
    messages.create!(
      role: "assistant",
      content: content,
      model_id: participant.model_id,
      conversation_participant: participant,
      round_number: round_num
    )
  end
end
```

### Phase 2: UX Enhancements

#### 2.1 Consistent Round Display
**Priority:** High
**Files:** `app/views/conversations/_message.html.erb`, `app/views/conversations/_messages.html.erb`

- Use `message.round_number` directly instead of calculating in views
- Add round progress indicators in message headers
- Show "Round X of Y" consistently across all views

#### 2.2 Enhanced Auto-Continue
**Priority:** Medium
**Files:** `app/javascript/controllers/auto_continue_controller.js`

- Simplify auto-continue logic using actual round completion
- Better error handling when rounds don't advance
- Visual feedback for round completion

#### 2.3 Improved Loading States
**Priority:** Low
**Files:** `app/views/shared/_streaming_indicator.html.erb`, `app/views/conversations/_controls.html.erb`

- Show which participant is currently speaking
- Better streaming indicators with participant context
- Round-by-round progress visualization

### Phase 3: Robustness & Testing

#### 3.1 Enhanced Error Handling
**Priority:** Medium
**Files:** `app/models/conversation.rb`

```ruby
# Add to Conversation model
def validate_round_integrity!
  participants.each do |participant|
    (1..current_round).each do |round_num|
      unless participant.has_spoken_in_round?(round_num)
        raise "Participant #{participant.name} missing message for round #{round_num}"
      end
    end
  end
end
```

#### 3.2 Background Job Improvements
**Priority:** Medium
**Files:** `app/jobs/chat_stream_job.rb`

```ruby
# Enhanced ChatStreamJob
class ChatStreamJob < ApplicationJob
  retry_on StandardError, wait: 5.seconds, attempts: 3
  
  def perform(conversation_id)
    conversation = Conversation.find(conversation_id)
    
    begin
      conversation.generate_one_round!
      conversation.validate_round_integrity!
    rescue => e
      conversation.update!(status: :failed)
      raise e
    end
  end
end
```

#### 3.3 Comprehensive Testing
**Priority:** Low
**Files:** `spec/` directory

- ✅ Already added unit specs for round management (`spec/models/conversation_spec.rb`)
- Add integration specs for full conversation flows
- Add feature specs for auto-continue functionality

## Implementation Priority

### High Priority
1. Fix round logic inconsistencies (Phase 1.1-1.2)
2. Improve speaker selection reliability (Phase 1.2)
3. Simplify round display in views (Phase 2.1)

### Medium Priority
4. Enhanced auto-continue UX (Phase 2.2)
5. Better error handling (Phase 3.1)
6. Background job improvements (Phase 3.2)

### Low Priority
7. Advanced UX improvements (Phase 2.3)
8. Integration testing (Phase 3.3)

## Key Files to Modify

- `app/models/conversation.rb` - Core round logic
- `app/models/conversation_participant.rb` - Speaker selection helpers  
- `app/views/conversations/_message.html.erb` - Round display
- `app/javascript/controllers/auto_continue_controller.js` - UX improvements
- `app/jobs/chat_stream_job.rb` - Error handling

## Testing Status

- ✅ **Unit specs completed:** `spec/models/conversation_spec.rb` includes comprehensive tests for round management logic
- ⏳ **Integration specs needed:** Full conversation flow testing
- ⏳ **Feature specs needed:** Auto-continue functionality testing

---

*This plan addresses the root causes of round management complexity while improving user experience and system reliability.*