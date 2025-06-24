require 'rails_helper'

RSpec.describe 'Models', type: :request do
  before do
    # Stub RubyLLM::Models.all to return test data with all required attributes
    models_data = [
      OpenStruct.new(
        id: 'openai/gpt-4o',
        name: 'OpenAI: GPT-4o',
        provider: 'openai',
        family: 'GPT-4',
        context_window: 128000,
        max_output_tokens: 4096,
        capabilities: [ 'text-generation', 'vision' ],
        pricing: OpenStruct.new(
          text_tokens: OpenStruct.new(
            standard: OpenStruct.new(
              input_per_million: '5.00',
              output_per_million: '15.00'
            )
          )
        )
      ),
      OpenStruct.new(
        id: 'anthropic/claude-3-5-sonnet',
        name: 'Anthropic: Claude 3.5 Sonnet',
        provider: 'anthropic',
        family: 'Claude',
        context_window: 200000,
        max_output_tokens: 4096,
        capabilities: [ 'text-generation' ],
        pricing: OpenStruct.new(
          text_tokens: OpenStruct.new(
            standard: OpenStruct.new(
              input_per_million: '3.00',
              output_per_million: '15.00'
            )
          )
        )
      )
    ]
    allow(RubyLLM::Models).to receive(:all).and_return(models_data)
  end

  it 'displays available models' do
    get models_path
    expect(response).to have_http_status(:success)
    expect(response.body).to include('OpenAI: GPT-4o')
    expect(response.body).to include('Anthropic: Claude 3.5 Sonnet')
  end
end
