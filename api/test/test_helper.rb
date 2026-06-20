ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

# Every test runs offline. We never want to hit the real Apify / Nominatim /
# Google Places / Claude endpoints — a test that needs one must stub it
# explicitly. allow_localhost keeps integration requests (Rack) working.
WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    # Tests build the few records they need inline (no fixtures), keeping each
    # case explicit about the data it depends on.
  end
end
