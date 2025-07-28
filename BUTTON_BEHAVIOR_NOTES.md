# Button Display Logic and Conversation Flow - Fixed

## Problem Summary
The button display logic was showing round progression incorrectly. The issue was that the "continue" button was only having one participant respond instead of performing a complete round.

## Solution Implemented

### Changes Made:

1. **Controller Updates** (`app/controllers/conversations_controller.rb`):
   - `start` action now calls `perform_round!` after starting the conversation
   - `continue` action now calls `perform_round!` instead of `have_current_speaker_respond!`

2. **View Updates** (`app/views/conversations/_conversation_frame.html.erb`):
   - Start button text: "Start Conversation >>"
   - Continue button text: "Play Round <%= conversation.current_round %> >>"

### Expected Behavior:

1. **Initial State**: 
   - `current_round = 1`, no messages
   - Button shows: "Start Conversation >>"

2. **After clicking Start**:
   - Performs round 1 (both participants speak)
   - `current_round = 2` 
   - Button shows: "Play Round 2 >>"

3. **After clicking Continue**:
   - Performs round 2 (both participants speak)
   - `current_round = 3`
   - Button shows: "Play Round 3 >>"

4. **And so on** until `max_rounds` is reached

### Key Insight:
The button now correctly shows the round number that will be played when clicked, and clicking the button performs the entire round (all participants speak) rather than just one participant.

## Testing Status:
- ✅ Conversation flow specs pass
- ✅ Round progression logic works correctly
- ✅ Button display shows correct round numbers

## Notes:
- The `current_round` field represents the next round to be played
- `perform_round!` handles all participants speaking in turn order
- Round advancement happens automatically after all participants speak
- Conversation completes when `current_round > max_rounds`