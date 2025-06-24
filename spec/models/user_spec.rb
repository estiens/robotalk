require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'validations' do
    # Create a user before each test to check for uniqueness
    subject { create(:user) }

    it { should validate_presence_of(:email) }
    it { should validate_uniqueness_of(:email) }
    it { should have_secure_password }
  end

  describe 'associations' do
    it { should have_many(:conversations).dependent(:destroy) }
  end

  describe '.anonymous' do
    it 'finds or creates an anonymous user' do
      anonymous_user = User.anonymous
      expect(anonymous_user).to be_persisted
      expect(anonymous_user.email).to eq('anonymous@roboconvo.local')
    end

    it 'finds the existing anonymous user on subsequent calls' do
      user1 = User.anonymous
      user2 = User.anonymous
      expect(user2.id).to eq(user1.id)
    end
  end
end
