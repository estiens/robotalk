module AuthenticationHelpers
  def create_user
    User.create!(
      email: "test@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  # For controller/request specs
  def sign_in(user)
    session[:user_id] = user.id if respond_to?(:session)
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers, type: :system
  config.include AuthenticationHelpers, type: :feature
  config.include AuthenticationHelpers, type: :request
end
