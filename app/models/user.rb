class User < ApplicationRecord
  has_secure_password

  has_many :conversations, dependent: :destroy

  validates :email, presence: true, uniqueness: true

  after_initialize :set_defaults

  def self.anonymous
    find_or_create_by(email: "anonymous@roboconvo.local") do |user|
      user.password = SecureRandom.hex(16)
    end
  end

  private

  def set_defaults
    self.default_model ||= "claude-sonnet-4-20250514" if new_record?
  end
end
