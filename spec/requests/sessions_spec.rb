# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Sessions' do
  describe 'GET /login' do
    it 'returns http success' do
      begin
        get '/login'
      rescue => e
        puts "EXCEPTION: #{e.class}: #{e.message}"
        puts e.backtrace.join("\n")
        raise
      end
      puts "Status: #{response.status}"
      puts "Body: #{response.body[0..500]}"
      puts "Session user_id: #{session[:user_id]}"
      expect(response).to have_http_status(:success)
    end
  end

  describe 'POST /login' do
    it 'returns redirect for invalid credentials' do
      post '/login', params: { session: { email: 'test@example.com', password: 'wrong' } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'DELETE /logout' do
    it 'returns redirect' do
      delete '/logout'
      expect(response).to have_http_status(:found)
    end
  end
end
