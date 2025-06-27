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
    **{
      # Chrome options
      browser_options: {
        'no-sandbox' => nil,
        'disable-gpu' => nil,
        'disable-dev-shm-usage' => nil,
        'disable-web-security' => nil,
        'disable-features=VizDisplayCompositor' => nil
      },

      # Cuprite options
      headless: !ENV['HEADLESS_CHROME'].in?([ '0', 'false' ]),
      slowmo: ENV['SLOWMO']&.to_f || 0,
      timeout: 30,
      js_errors: true,

      # Window size
      window_size: [ 1400, 1400 ],

      # Process timeout
      process_timeout: 30,

      # Inspector (for debugging, set INSPECTOR=true)
      inspector: ENV['INSPECTOR'].in?([ '1', 'true' ]),

      # URL whitelist (allow all for flexibility)
      url_whitelist: [ 'http://127.0.0.1', 'http://localhost' ]
    }
  )
end

# Alternative Cuprite driver for tests requiring different browser options
Capybara.register_driver :cuprite_chrome_debug do |app|
  Capybara::Cuprite::Driver.new(
    app,
    **{
      browser_options: {
        'no-sandbox' => nil,
        'disable-gpu' => nil,
        'disable-dev-shm-usage' => nil,
        'remote-debugging-port' => 9222
      },
      headless: false,  # Non-headless for debugging
      timeout: 30,
      js_errors: true,
      window_size: [ 1400, 1400 ],
      process_timeout: 30,
      inspector: true
    }
  )
end

# Driver-specific configurations for different test scenarios
Capybara.register_driver :cuprite_slow do |app|
  Capybara::Cuprite::Driver.new(
    app,
    **{
      browser_options: {
        'no-sandbox' => nil,
        'disable-gpu' => nil,
        'disable-dev-shm-usage' => nil
      },
      headless: !ENV['HEADLESS_CHROME'].in?([ '0', 'false' ]),
      slowmo: 0.5,  # Slow down for debugging
      timeout: 60,
      js_errors: true,
      window_size: [ 1400, 1400 ],
      process_timeout: 60,
      inspector: ENV['INSPECTOR'].in?([ '1', 'true' ])
    }
  )
end

# Configure RSpec metadata for different drivers
RSpec.configure do |config|
  # Use JS driver for tests marked with js: true
  config.before(:each, type: :feature) do |example|
    if example.metadata[:js]
      Capybara.current_driver = :cuprite
    end
  end

  # Use slow driver for tests that need more time (LLM streaming, etc.)
  config.before(:each, type: :feature, slow: true) do
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
    if Capybara.current_driver == :cuprite || Capybara.current_driver == :cuprite_slow
      page.driver.quit if page.driver.respond_to?(:quit)
    end
  end
end

# Helper method to switch drivers mid-test if needed
def using_driver(driver, &block)
  original_driver = Capybara.current_driver
  Capybara.current_driver = driver
  yield
ensure
  Capybara.current_driver = original_driver
end

# Debug helper
def save_and_open_screenshot(name = "screenshot")
  timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
  filename = "#{name}_#{timestamp}.png"
  save_screenshot(filename)
  puts "Screenshot saved: #{filename}"
end
