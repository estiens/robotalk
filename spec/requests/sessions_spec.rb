require 'rails_helper'

RSpec.describe "Sessions", type: :request do
  describe "GET /login" do
    it "returns http success" do
      get "/login"
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /login" do
    it "returns redirect for invalid credentials" do
      post "/login", params: { session: { email: "test@example.com", password: "wrong" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /logout" do
    it "returns redirect" do
      delete "/logout"
      expect(response).to have_http_status(:found)
    end
  end
end
