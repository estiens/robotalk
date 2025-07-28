# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Models' do
  it 'displays available models' do
    get models_path
    expect(response).to have_http_status(:success)
    expect(response.body).to include('OpenAI: GPT-4o')
    expect(response.body).to include('Anthropic: Claude 3.5 Sonnet')
  end
end
