# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RoboConvo is a Ruby on Rails 8.0.2 application that facilitates automated conversations between different AI/LLM models. It uses the `ruby_llm` gem to integrate with multiple LLM providers and allows users to create multi-participant conversations where AI models communicate with each other in structured rounds.

## Key Development Commands

```bash
# Initial setup
bin/setup              # Installs dependencies, prepares database, starts dev server

# Development
bin/dev               # Starts Rails server + Tailwind CSS watcher (uses Procfile.dev)
bin/rails console     # Rails console
bin/rails server      # Rails server only (without CSS watcher)

# Database
bin/rails db:migrate  # Run migrations
bin/rails db:prepare  # Create, migrate, and seed database

# Testing
bin/rspec            # Run all tests
bin/rspec spec/models/conversation_spec.rb  # Run specific test file

# Code Quality
bin/rubocop          # Run linter
bin/rubocop -a       # Auto-fix linting issues
bin/brakeman         # Security vulnerability scanner

# Deployment
bin/kamal deploy     # Deploy to production
```

## Architecture Overview

### Core Models and Relationships

#### Conversation (`app/models/conversation.rb`)
- **Primary orchestrator** for multi-model AI conversations
- Key fields: `max_rounds` (1-50), `conversation_topic`
- **Relationships**: `has_many :messages`, `has_many :participants`
- **Key methods**:
  - `current_round`: Counts assistant messages to track progress
  - `can_continue?`: Checks if conversation can proceed based on max_rounds
  - `next_speaker`: Implements round-robin turn management using turn_order
  - `can_start?`: Validates minimum 2 participants exist

#### ConversationParticipant (`app/models/conversation_participant.rb`)
- **Represents each AI model** participating in a conversation
- Key fields: `model` (LLM identifier), `name` (participant name), `turn_order` (speaking sequence), `system_prompt`, `character_prompt`
- **Core method**: `system_prompt_with_topic` - builds complete system prompt by combining base prompt + character + topic + custom instructions
- **Base system prompt** includes participant name, model identification, and conversation guidelines

#### Message (`app/models/message.rb`)
- **Stores conversation history** with `role` ("system", "user", "assistant"), `content`, `model`, `metadata` (JSON)
- Chronological conversation history with metadata tracking

### RubyLLM Integration Patterns

#### Configuration (`config/initializers/ruby_llm.rb`)
```ruby
RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
  config.gemini_api_key = ENV.fetch("GEMINI_API_KEY", nil)
  config.deepseek_api_key = ENV.fetch("DEEPSEEK_API_KEY", nil)
  config.openrouter_api_key = ENV.fetch("OPENROUTER_API_KEY", nil)
end
```

#### Core Usage Patterns (`app/controllers/conversations_controller.rb`)
```ruby
# Get available models
RubyLLM::Models.all.sort_by(&:name)

# Create chat instance with specific provider/model
chat = RubyLLM.chat(provider: :openrouter, model: model)

# Streaming response pattern
response_content = ""
chat.ask(prompt) do |chunk|
  response_content += chunk.content
end
```

#### Model Management (`app/helpers/conversations_helper.rb`)
```ruby
# Get friendly model names
model_info = RubyLLM::Models.all.find { |m| m.id == model_identifier }
return model_info.name if model_info
```

### Frontend Architecture (Hotwire + Stimulus)

#### Key Stimulus Controllers
- **`auto_continue_controller.js`**: Automated conversation flow with localStorage state persistence
- **`conversation_controls_controller.js`**: Manual conversation controls with loading state management
- **`loading_indicator_controller.js`**: Visual feedback during LLM response generation
- **`view_mode_controller.js`**: Switches between history/live views with localStorage preferences
- **`expandable_message_controller.js`**: Collapsible long messages

#### Turbo Integration
- **Turbo Streams** for real-time UI updates without page refresh
- **Turbo Frames** for partial page updates during conversation flow
- Import maps for JavaScript management (no bundler required)

### Database Architecture
- **SQLite3** in development/test with separate production databases
- **Three core tables**: conversations, conversation_participants, messages
- **Constraints**: unique model per conversation, unique turn order per conversation
- **Solid Queue** for background jobs, **Solid Cache** for caching, **Solid Cable** for WebSockets

### Conversation Flow Patterns

#### Starting Conversations (`ConversationsController#start`)
1. Validates minimum 2 participants via `can_start?`
2. Creates system messages for all participants using `system_prompt_with_topic`
3. Initiates first round with opening prompt
4. Uses `generate_llm_response` for LLM API calls

#### Continuing Conversations (`ConversationsController#continue`)
1. Check `can_continue?` based on max_rounds
2. Get next speaker via `next_speaker` (round-robin)
3. Generate response based on last message content
4. Track metadata (response time, model info)

### Deployment Architecture
- **Docker containerized** with multi-stage build
- **Kamal deployment** (config in `config/deploy.yml`)
- **Thruster** for HTTP caching/compression
- **Persistent volume** for SQLite storage at `/rails/storage`
- **Tailwind CSS** integrated with Rails asset pipeline

## Important Environment Variables
- `OPENAI_API_KEY`
- `ANTHROPIC_API_KEY`
- `GEMINI_API_KEY`
- `DEEPSEEK_API_KEY`
- `OPENROUTER_API_KEY`

## Testing Approach
- **RSpec** for all tests with `bin/rspec`
- **VCR** for recording/mocking LLM API calls
- **FactoryBot** for test data generation
- **WebMock** for HTTP request stubbing
- Feature specs test full conversation flow
- **IMPORTANT**: Use `data-test` attributes for element selection in feature specs, NOT string matching
  - Good: `expect(page).to have_selector('[data-test="start-conversation-button"]')`
  - Bad: `expect(page).to have_content('Start Conversation')`
  - This prevents tests from breaking when UI text changes
- Always run tests before committing changes

## Conversation Templates System

### Template Types
The app includes pre-built templates to make setup easier for users who don't want to write custom prompts:

#### Dialogue Types (`lib/conversation_templates.rb`)
- **Structured**: `debate`, `friendly_debate` - Formal and casual argumentation formats
- **Collaborative**: `brainstorm`, `problem_solving` - Creative and analytical collaboration
- **Q&A**: `interview`, `teaching_learning`, `socratic_inquiry` - Learning and inquiry formats
- **Creative**: `storytelling`, `casual_chat` - Narrative and social interaction
- **Analytical**: `analysis_critique`, `philosophical_inquiry` - Deep examination formats

#### Character Archetypes
- **Thinking Styles**: `analytical`, `creative`, `pragmatic`, `philosophical`
- **Communication Styles**: `socratic`, `collaborative`, `skeptical`, `synthesizer`
- **Professional Personas**: `researcher`, `educator`, `entrepreneur`, `philosopher`
- **Personality Traits**: `optimistic`, `cautious`, `curious`, `contrarian`

Each archetype includes a `default_name` (e.g., "Logic", "Nova", "Guardian") and detailed personality `prompt`.

#### Suggested Combinations
Pre-configured pairings like "Classic Debate" (Analytical + Philosophical) or "Creative Brainstorm" (Creative + Synthesizer).

### Usage Patterns
- **Fully Custom**: Users write all prompts manually (existing workflow)
- **Template + Custom**: Select templates, then modify the generated prompts
- **Pure Template**: Select dialogue type + character archetypes, system auto-fills everything

## Key Files to Understand
- `app/controllers/conversations_controller.rb` - Main conversation logic and RubyLLM integration
- `app/models/conversation.rb` - Conversation orchestration and round management
- `app/models/conversation_participant.rb` - Participant management, naming, and system prompt building
- `app/helpers/conversations_helper.rb` - Model name resolution and UI helpers
- `app/helpers/templates_helper.rb` - Template system helper methods
- `lib/conversation_templates.rb` - Dialogue types, character archetypes, and suggested combinations
- `config/initializers/ruby_llm.rb` - Multi-provider LLM configuration
- `app/javascript/controllers/` - Stimulus controllers for interactive behavior