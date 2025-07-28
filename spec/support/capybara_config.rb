# frozen_string_literal: true

require 'capybara/rspec'
require 'capybara/cuprite'

# Configure Capybara
Capybara.configure do |config|
  # Default driver for non-JS tests (faster)
  config.default_driver = :rack_test

  # JavaScript driver for tests that need JS
  config.javascript_driver = :cuprite

  # Default timeouts
  config.default_max_wait_time = 5

  # Server configuration
  config.server = :puma, { Silent: true }
  config.server_port = 9887 + ENV['TEST_ENV_NUMBER'].to_i

  # Asset host for tests
  config.asset_host = "http://localhost:#{config.server_port}"
end

# Configure Cuprite (Chrome DevTools Protocol)
Capybara.register_driver :cuprite do |app|
  Capybara::Cuprite::Driver.new(
    app,
    browser_options: {
      'no-sandbox' => nil,
      'disable-gpu' => nil,
      'disable-dev-shm-usage' => nil,
      'disable-web-security' => nil,
      'disable-features=VizDisplayCompositor' => nil
    },

    # Cuprite options
    headless: !ENV['HEADLESS_CHROME'].in?(%w[0 false]),
    slowmo: ENV['SLOWMO']&.to_f || 0,
    timeout: 30,
    js_errors: true,

    # Window size
    window_size: [1400, 1400],

    # Process timeout
    process_timeout: 30,

    # Inspector (for debugging, set INSPECTOR=true)
    inspector: ENV['INSPECTOR'].in?(%w[1 true]),

    # URL whitelist (allow all for flexibility)
    url_whitelist: ['http://127.0.0.1', 'http://localhost']
  )
end

# Alternative Cuprite driver for tests requiring different browser options
Capybara.register_driver :cuprite_chrome_debug do |app|
  Capybara::Cuprite::Driver.new(
    app,
    browser_options: {
      'no-sandbox' => nil,
      'disable-gpu' => nil,
      'disable-dev-shm-usage' => nil,
      'remote-debugging-port' => 9222
    },
    headless: false, # Non-headless for debugging
    timeout: 30,
    js_errors: true,
    window_size: [1400, 1400],
    process_timeout: 30,
    inspector: true
  )
end

# Driver-specific configurations for different test scenarios
Capybara.register_driver :cuprite_slow do |app|
  Capybara::Cuprite::Driver.new(
    app,
    browser_options: {
      'no-sandbox' => nil,
      'disable-gpu' => nil,
      'disable-dev-shm-usage' => nil
    },
    headless: !ENV['HEADLESS_CHROME'].in?(%w[0 false]),
    slowmo: 0.5, # Slow down for debugging
    timeout: 60,
    js_errors: true,
    window_size: [1400, 1400],
    process_timeout: 60,
    inspector: ENV['INSPECTOR'].in?(%w[1 true])
  )
end

# Configure RSpec metadata for different drivers
RSpec.configure do |config|
  # Monkey patch the Ferrum::Browser class to handle nil contexts during reset
  config.before(:suite) do
    if defined?(Ferrum::Browser)
      Ferrum::Browser.class_eval do
        alias_method :original_reset, :reset

        def reset
          # Skip reset if contexts is nil to avoid the error
          if defined?(@contexts) && @contexts.nil?
            Rails.logger.debug { 'Skipping Ferrum::Browser#reset due to nil contexts' }
            return
          end
          original_reset
        end
      end
    end
  end

  # Use JS driver for tests marked with js: true
  config.before(:each, type: :feature) do |example|
    Capybara.current_driver = :cuprite if example.metadata[:js]
  end

  # Use slow driver for tests that need more time (LLM streaming, etc.)
  config.before(:each, :slow, type: :feature) do
    Capybara.current_driver = :cuprite_slow
    Capybara.default_max_wait_time = 30
  end

  # Reset driver after each test
  config.after(:each, type: :feature) do
    Capybara.use_default_driver
    Capybara.default_max_wait_time = 5
  end

  # Clean up cuprite sessions properly
  config.after(:each, type: :feature) do
    if %i[cuprite cuprite_slow cuprite_chrome_debug].include?(Capybara.current_driver)
      begin
        # Just quit the driver without trying to reset
        page.driver.quit if page.driver.respond_to?(:quit)
      rescue StandardError => e
        Rails.logger.debug { "Driver cleanup failed: #{e.message}" }
      end
    end
  end

  # Add a specific hook to handle the Ferrum/Cuprite 'contexts' being nil issue
  config.prepend_after do
    # Skip if we're not using a Cuprite driver
    next unless %i[cuprite cuprite_slow cuprite_chrome_debug].include?(Capybara.current_driver)

    # Only proceed if page exists and has the expected structure
    next unless defined?(page) && page.driver.respond_to?(:browser)

    # Check for nil contexts to prevent the error
    if page.driver.browser.respond_to?(:contexts) && page.driver.browser.contexts.nil?
      # Apply a safer cleanup approach
      begin
        # Force browser to quit instead of reset
        page.driver.browser.quit if page.driver.browser.respond_to?(:quit)
      rescue StandardError => e
        Rails.logger.debug { "Alternative browser cleanup failed: #{e.message}" }
      end
    end
  end
end

# Helper method to switch drivers mid-test if needed
def using_driver(driver)
  original_driver = Capybara.current_driver
  Capybara.current_driver = driver
  yield
ensure
  Capybara.current_driver = original_driver
end

# Debug helper
def save_and_open_screenshot(name = 'screenshot')
  timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
  filename = "#{name}_#{timestamp}.png"
  save_screenshot(filename)
  puts "Screenshot saved: #{filename}"
end
