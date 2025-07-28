# frozen_string_literal: true

module CapybaraHelpers
  # Default timeouts for different types of operations
  DEFAULT_TIMEOUT = 5
  LONG_TIMEOUT = 30     # For LLM responses, streaming operations
  QUICK_TIMEOUT = 2     # For immediate UI changes

  # Find element by data-test attribute with configurable timeout
  def find_test_element(test_id, timeout: DEFAULT_TIMEOUT, **)
    find("[data-test='#{test_id}']", wait: timeout, **)
  end

  # Check if element with data-test attribute exists
  def has_test_element?(test_id, timeout: DEFAULT_TIMEOUT, **)
    page.has_selector?("[data-test='#{test_id}']", wait: timeout, **)
  end

  # Check if element with data-test attribute does not exist
  def has_no_test_element?(test_id, timeout: DEFAULT_TIMEOUT, **)
    page.has_no_selector?("[data-test='#{test_id}']", wait: timeout, **)
  end

  # Click element by data-test attribute
  def click_test_element(test_id, timeout: DEFAULT_TIMEOUT, **)
    find_test_element(test_id, timeout: timeout, **).click
  end

  # Find and click hidden element (useful for hover-revealed buttons like delete)
  def click_hidden_test_element(test_id, timeout: DEFAULT_TIMEOUT)
    find("[data-test='#{test_id}']", visible: false, wait: timeout).click
  end

  # Wait for element to appear with data-test attribute
  def wait_for_test_element(test_id, timeout: DEFAULT_TIMEOUT, **)
    expect(page).to have_css("[data-test='#{test_id}']", wait: timeout, **)
  end

  # Wait for element to disappear with data-test attribute
  def wait_for_test_element_removal(test_id, timeout: DEFAULT_TIMEOUT, **)
    expect(page).to have_no_selector("[data-test='#{test_id}']", wait: timeout, **)
  end

  # Fill in form field by data-test attribute
  def fill_test_field(test_id, value, timeout: DEFAULT_TIMEOUT)
    find_test_element(test_id, timeout: timeout).fill_in(with: value)
  end

  # Select option from dropdown by data-test attribute
  def select_test_option(test_id, option, timeout: DEFAULT_TIMEOUT)
    find_test_element(test_id, timeout: timeout).select(option)
  end

  # Conversation-specific helpers
  def find_conversation_card(conversation_id, timeout: DEFAULT_TIMEOUT)
    find_test_element("conversation-card-#{conversation_id}", timeout: timeout)
  end

  def click_conversation_delete(conversation_id, timeout: DEFAULT_TIMEOUT)
    within_conversation_card(conversation_id) do
      click_hidden_test_element('delete-conversation-button', timeout: timeout)
    end
  end

  def click_conversation_start(conversation_id, timeout: DEFAULT_TIMEOUT)
    within_conversation_card(conversation_id) do
      click_test_element('start-conversation-button', timeout: timeout)
    end
  end

  def click_conversation_continue(conversation_id = nil, timeout: LONG_TIMEOUT)
    if conversation_id
      within_conversation_card(conversation_id) do
        click_test_element('continue-conversation-button', timeout: timeout)
      end
    else
      click_test_element('continue-conversation-button', timeout: timeout)
    end
  end

  def within_conversation_card(conversation_id, &)
    within("[data-test='conversation-card-#{conversation_id}']", &)
  end

  # Wait for streaming operations to complete
  def wait_for_streaming_completion(timeout: LONG_TIMEOUT)
    # Wait for streaming indicator to appear
    wait_for_test_element('streaming-indicator', timeout: QUICK_TIMEOUT)
    # Wait for it to disappear
    wait_for_test_element_removal('streaming-indicator', timeout: timeout)
  end

  # Wait for conversation round progression
  def wait_for_round_indicator(timeout: LONG_TIMEOUT)
    wait_for_test_element('round-indicator', timeout: timeout)
  end

  # Authentication helpers
  def sign_in_as_anonymous
    # The app automatically creates anonymous users, so just visit any page
    visit conversations_path
  end

  def create_test_conversation(user: nil, topic: 'Test Topic', **attrs)
    user ||= User.find_or_create_by(email: 'anonymous@roboconvo.local') { |u| u.password = 'password' }
    create('conversation', user: user, conversation_topic: topic, **attrs)
  end

  # Generic form helpers
  def submit_form_with_test_button(button_test_id, timeout: DEFAULT_TIMEOUT)
    click_test_element(button_test_id, timeout: timeout)
  end

  # Modal and confirmation helpers (for when JS driver is enabled)
  def accept_confirmation_and_click(test_id, timeout: DEFAULT_TIMEOUT)
    accept_confirm do
      click_test_element(test_id, timeout: timeout)
    end
  end

  def dismiss_confirmation_and_click(test_id, timeout: DEFAULT_TIMEOUT)
    dismiss_confirm do
      click_test_element(test_id, timeout: timeout)
    end
  end

  # Check for flash messages (when flash display is added to layout)
  def expect_flash_message(message, type: :notice, timeout: DEFAULT_TIMEOUT)
    expect(page).to have_css(".flash-#{type}", text: message, wait: timeout)
  end

  # Database assertion helpers
  def expect_record_count_change(model_class, change_by:, &)
    expect(&).to change { model_class.count }.by(change_by)
  end

  def expect_record_to_exist(model_class, id)
    expect(model_class.exists?(id)).to be true
  end

  def expect_record_not_to_exist(model_class, id)
    expect(model_class.exists?(id)).to be false
  end
end

RSpec.configure do |config|
  config.include CapybaraHelpers, type: :feature
  config.include CapybaraHelpers, type: :system
end
