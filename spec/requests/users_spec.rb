# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Users' do
  describe 'GET /signup' do
    it 'returns http success' do
      get '/signup'
      expect(response).to have_http_status(:success)
    end
  end

  describe 'POST /signup' do
    it 'creates a user with valid params' do
      user_params = { user: { email: 'test@example.com', password: 'password' } }
      expect do
        post '/signup', params: user_params
      end.to change(User, :count).by(1)
      expect(response).to have_http_status(:found)
    end
  end
end
