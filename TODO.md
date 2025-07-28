# RoboConvo Development TODO

This file tracks all identified issues and improvements needed for the RoboConvo AI-to-AI conversation platform.

*Last Updated: 2025-07-28 - Generated from comprehensive code review using Claude Code + Gemini Pro*

## 🚨 CRITICAL (Fix Immediately)

### Backend - Conversation Breaking Issues

**1. Round Logic Bug** - `app/services/round_service.rb:29-32`
- **Issue**: `have_current_speaker_respond!` advances round after ANY participant speaks instead of after ALL participants complete the round
- **Impact**: Completely breaks multi-participant conversations, participants get skipped
- **Priority**: CRITICAL - Fix today
- **Files**: `app/services/round_service.rb`

**2. API Key Security Risk** - `app/services/llm_service.rb:20`
- **Issue**: Direct OpenRouter client instantiation without proper credential management
- **Impact**: Potential API key exposure in logs/errors, security vulnerability
- **Priority**: CRITICAL - Fix today
- **Files**: `app/services/llm_service.rb`

**3. Conversation State Deadlock** - `app/controllers/conversations_controller.rb:132-143`
- **Issue**: Failed LLM calls leave conversations in `in_progress` status but unable to continue
- **Impact**: Users can't recover from API failures without manual intervention
- **Priority**: CRITICAL - Fix today
- **Files**: `app/controllers/conversations_controller.rb`

**4. Message Model Migration Incomplete** - Database schema inconsistency
- **Issue**: Migrations to remove `type` column and `tool_calls` table haven't been run
- **Impact**: Schema inconsistency, potential database errors
- **Priority**: CRITICAL - Fix today
- **Files**: `db/migrate/20250628001134_remove_type_from_messages.rb`, `db/schema.rb`

## ⚡ HIGH PRIORITY (This Week)

### Backend - Performance & Data Integrity

**5. N+1 Query Performance Issue** - `app/services/round_manager.rb:15-17`
- **Issue**: `next_speaker` queries database separately for each participant  
- **Impact**: Conversation loading becomes sluggish with 3+ participants
- **Files**: `app/services/round_manager.rb`, `app/models/conversation_participant.rb`

**6. Missing Database Indexes**
- **Issue**: Critical query columns lack proper indexes
- **Impact**: Poor query performance
- **Indexes Needed**:
  - `(conversation_id, round_number)` on messages
  - `(conversation_id, turn_order)` on conversation_participants
  - `conversation_participant_id` on messages

**7. Round Completion Race Condition** - `app/services/round_service.rb`
- **Issue**: JSON queries may not work correctly across SQLite/PostgreSQL
- **Impact**: Race conditions in round completion detection
- **Files**: `app/models/conversation_participant.rb`, `app/services/round_service.rb`

**8. Add Conversation Locking Mechanism**
- **Issue**: No protection against concurrent updates to same conversation
- **Impact**: Data corruption, inconsistent state
- **Files**: `app/models/conversation.rb`, `app/services/round_service.rb`

**9. Update Test Suite** - Remove tool_calls references
- **Issue**: Tests still reference removed STI functionality
- **Impact**: Test failures, outdated test coverage
- **Files**: `spec/models/message_spec.rb`, other test files

**10. Fix Empty Migration** - `db/migrate/*drop_tool_calls_table.rb`
- **Issue**: Migration file exists but has no implementation
- **Impact**: Database cleanup incomplete
- **Files**: Migration file needs implementation

## 📈 MEDIUM PRIORITY (Next Sprint)

### Backend - Code Quality & Features

**10. Model Uniqueness Validation**
- **Issue**: No validation prevents same model being added twice to conversation
- **Files**: `app/models/conversation_participant.rb`

**11. Context Window Management**
- **Issue**: Hard-coded 10-message limit without token counting
- **Impact**: May truncate important context or exceed API limits
- **Files**: `app/services/llm_service.rb`

**12. Current Round Field Tracking**
- **Issue**: `current_round` field may drift from actual calculated state
- **Files**: `app/models/conversation.rb`, `app/services/round_service.rb`

**13. Error Handling Improvements**
- **Issue**: LLM failures create error messages but don't properly fail conversation
- **Files**: `app/services/llm_service.rb`, `app/services/round_service.rb`

**14. LLM Service Abstraction**
- **Issue**: Direct coupling to OpenRouter, should support multiple providers
- **Files**: `app/services/llm_service.rb`

## 🔧 LOW PRIORITY (Future Iterations)

### Backend - Nice to Have

**15. Turn Order Validation**
- **Issue**: No validation ensuring sequential turn_order (1,2,3...) without gaps
- **Files**: `app/models/conversation_participant.rb`

**16. API Retry Logic**
- **Issue**: No retry logic for transient API failures
- **Files**: `app/services/llm_service.rb`

**17. Request/Response Logging**
- **Issue**: No comprehensive logging for LLM API calls
- **Files**: `app/services/llm_service.rb`

**18. Memory Management**
- **Issue**: Background jobs may have memory leaks with large conversations
- **Files**: `app/jobs/generate_conversation_job.rb`

## 🎨 FRONTEND/UX ISSUES

### ⚡ HIGH PRIORITY (UX Improvements)

**19. UX Confusion: "Round 1" Before Start** - `app/views/conversations/_conversation_frame.html.erb:116`
- **Issue**: Shows "Round 1" when no messages exist yet
- **Impact**: Users think conversation already started
- **Files**: `app/views/conversations/_conversation_frame.html.erb`

**20. Accessibility Violations**
- **Issue**: Missing ARIA labels, keyboard navigation, screen reader support
- **Impact**: Unusable for vision-impaired users, compliance issues
- **Files**: All view templates and JavaScript controllers

### 📈 MEDIUM PRIORITY (UX Polish)

**21. Loading State Inconsistencies** 
- **Issue**: Loading state inconsistencies across multiple JS controllers
- **Impact**: Confusing user experience during operations
- **Files**: `app/javascript/controllers/`

**22. Message Truncation UX**
- **Issue**: 800-character truncation may cut mid-sentence
- **Impact**: Messages appear broken or incomplete
- **Files**: Message display components

**23. JavaScript Error Handling Gaps**
- **Issue**: Network failures not properly handled in frontend
- **Impact**: Silent failures, user confusion
- **Files**: All Stimulus controllers

### 🔧 LOW PRIORITY (UX Nice-to-Have)

**24. Heavy Animations Without Reduced-Motion**
- **Issue**: No respect for reduced-motion accessibility preferences
- **Files**: CSS and animation components

**25. Mobile Touch Targets**
- **Issue**: Touch targets potentially too small for mobile users
- **Files**: UI components and buttons

---

## 📋 IMPLEMENTATION NOTES

### Critical Bug Fix Examples

**Round Logic Fix (Item #1):**
```ruby
# In RoundService#have_current_speaker_respond!
# CURRENT (BROKEN):
if round_complete?
  advance_round!
end

# Should only advance after ALL participants speak in round
```

**Conversation State Deadlock Fix (Item #3):**
```ruby
# In ConversationsController rescue blocks
rescue StandardError => e
  Rails.logger.error "Failed to start conversation: #{e.message}"
  @conversation.fail!  # Add this line
  
  respond_to do |format|
    format.html { redirect_to @conversation, alert: "Failed to start conversation: #{e.message}" }
    # ... rest of error handling
  end
end
```

**API Security Fix (Item #2):**
```ruby
# Add proper credential management
class LlmService
  private
  
  def build_client
    @client ||= OpenRouter::Client.new(
      api_key: Rails.application.credentials.openrouter_api_key
    )
  end
end
```

**Database Indexes (Item #5):**
```ruby
# Add to new migration
add_index :messages, [:conversation_id, :round_number]
add_index :messages, :conversation_participant_id
add_index :conversation_participants, [:conversation_id, :turn_order]
```

---

## 🎨 UI/UX IMPROVEMENTS (Legacy Plans)

### ⚠️ Previous Issues Identified

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