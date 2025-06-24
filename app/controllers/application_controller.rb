class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :current_user, :logged_in?

  def current_user
    @current_user ||= begin
      if session[:user_id]
        User.find_by(id: session[:user_id])
      else
        # Create or find anonymous user
        anonymous_user = User.find_or_create_by(email: "anonymous@roboconvo.local") do |user|
          user.password = SecureRandom.hex(16)
        end
        session[:user_id] = anonymous_user.id
        anonymous_user
      end
    end
  end

  def logged_in?
    current_user.present?
  end

  def require_user
    if !logged_in?
      flash[:alert] = "You must be logged in to perform that action"
      redirect_to login_path
    end
  end
end
