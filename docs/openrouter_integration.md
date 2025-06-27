# OpenRouter Integration Documentation

This document outlines how RoboConvo integrates with OpenRouter for LLM functionality.

## Overview

RoboConvo uses the [open_router](https://github.com/OlympiaAI/open_router) Ruby gem to interface with OpenRouter's unified API for multiple LLM providers. This approach gives us direct control over message formatting, conversation history management, and error handling.

## Configuration

### Environment Variables

Required environment variables:

```bash
OPENROUTER_API_KEY=your_api_key_here
OPENROUTER_BASE_URL=https://openrouter.ai/api/v1  # Optional, defaults to OpenRouter
```

### Initializer

Located in `config/initializers/open_router.rb`:

```ruby
OpenRouter.configure do |config|
  config.access_token = ENV.fetch("OPENROUTER_API_KEY", nil)
  config.uri_base = ENV.fetch("OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1")
end
```

The `uri_base` can be overridden to use proxies like Helicone for monitoring and caching.

## LlmService Integration

The `LlmService` class handles all LLM interactions:

### Key Methods

- `generate_response`: Main entry point for generating LLM responses
- `build_messages`: Constructs message array with system prompt, conversation history, and user prompt
- `extract_content_from_response`: Handles different response formats from OpenRouter

### Message Format

OpenRouter expects messages in OpenAI-compatible format:

```ruby
[
  { role: "system", content: "System prompt with character and topic" },
  { role: "assistant", content: "Previous message", name: "Participant Name" },
  { role: "user", content: "Please continue the discussion..." }
]
```

### Response Handling

OpenRouter returns OpenAI-style responses:

```ruby
{
  "choices" => [
    {
      "message" => {
        "content" => "The actual response text"
      }
    }
  ],
  "usage" => { "total_tokens" => 150 },
  "model" => "openai/gpt-4o-mini"
}
```

## Supported Models

We maintain a curated list of models in `ConversationsController#get_available_models`:

### Current Models
- **OpenAI**: gpt-4o, gpt-4o-mini
- **Anthropic**: claude-3-5-sonnet, claude-3-haiku, claude-3-opus
- **Google**: gemini-pro-1.5, gemini-flash-1.5
- **Meta**: llama-3.1-405b-instruct, llama-3.1-70b-instruct
- **DeepSeek**: deepseek-r1-0528
- **Mistral**: mistral-large
- **Cohere**: command-r-plus

### Adding New Models

To add new models:
1. Update the `get_available_models` method in `ConversationsController`
2. Test with a sample conversation
3. Ensure the model supports the message format we use

## System Prompt Construction

System prompts are built in `ConversationParticipant#system_prompt_with_topic`:

```ruby
def system_prompt_with_topic
  [
    system_prompt,           # Base system prompt
    character_prompt,        # Character-specific instructions
    "Topic: #{conversation.conversation_topic}",
    conversation.dialogue_instructions
  ].compact.join("\n\n")
end
```

## Error Handling

The service includes comprehensive error handling:

1. **API Errors**: Catch exceptions from OpenRouter calls
2. **Response Parsing**: Handle different response formats
3. **Graceful Degradation**: Create error messages when LLM calls fail
4. **Logging**: Detailed logs for debugging

## Context Management

### Message History Limiting

We limit conversation history to the last 10 messages to manage context windows:

```ruby
conversation.messages.includes(:conversation_participant)
                    .order(:created_at)
                    .last(10)
```

### Future: Conversation Summarization

Plan to implement conversation summarization for long conversations:
- Periodically summarize older messages
- Preserve important context while reducing token usage
- Maintain full message history for UI display

## Testing Strategy

### Mocking in Tests

We mock OpenRouter calls in tests:

```ruby
let(:mock_client) { double("OpenRouter::Client") }
let(:mock_response) { { "choices" => [{ "message" => { "content" => "Test response" } }] } }

before do
  allow(OpenRouter::Client).to receive(:new).and_return(mock_client)
  allow(mock_client).to receive(:complete).and_return(mock_response)
end
```

### Integration Tests

Integration tests verify the full flow without mocking LlmService but still mock OpenRouter calls to avoid API usage.

## Monitoring and Observability

### Helicone Integration

To use Helicone for monitoring:

```bash
OPENROUTER_BASE_URL=https://oai.hconeai.com/v1
```

Add Helicone headers in the OpenRouter client configuration if needed.

### Logging

The service logs:
- Model selection and parameters
- Message count and content length
- Response metadata (tokens, model, timing)
- Errors with full stack traces

## Performance Considerations

### Request Optimization

- Limit conversation history to manage context windows
- Cache model list instead of fetching dynamically
- Use appropriate timeouts for different model speeds

### Response Handling

- Extract content efficiently from different response formats
- Store relevant metadata for analytics
- Handle streaming responses when implemented

## Future Enhancements

### Planned Features

1. **Streaming Responses**: Implement real-time response streaming
2. **Tool Calling**: Add support for function calling where supported
3. **Model-Specific Parameters**: Allow per-model configuration (temperature, max_tokens)
4. **Conversation Summarization**: Automatic context compression for long conversations
5. **Retry Logic**: Implement exponential backoff for failed requests

### Configuration Expansion

- Per-conversation model parameters
- Custom system prompt templates
- Model capability detection and routing

## Troubleshooting

### Common Issues

1. **API Key Issues**: Verify OPENROUTER_API_KEY is set
2. **Model Not Found**: Check model ID against supported models list
3. **Rate Limiting**: Implement backoff strategies
4. **Context Length**: Monitor token usage and implement summarization

### Debug Information

The `/conversations/:id/debug` endpoint provides detailed conversation state for troubleshooting.