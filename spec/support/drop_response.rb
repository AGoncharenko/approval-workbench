# Test-only Rack middleware around the Capybara server app. While armed, every decision POST closes the
# socket without any HTTP response, like a timeout or dropped connection. It stays armed until the test
# disarms it, because Chrome silently re-sends a POST once when a reused connection closes without a response.
#   :after_app  - the request runs and commits first (the response is lost)
#   :before_app - the request never reaches the app
class DropResponse
  class << self
    attr_accessor :mode

    # Same wrapper for the same app, so Capybara keeps reusing one server.
    def wrap(app) = app.is_a?(self) ? app : (@wrapped ||= {})[app] ||= new(app)
  end

  def initialize(app)
    @app = app
  end

  def call(env)
    mode = self.class.mode
    return @app.call(env) unless mode && env["REQUEST_METHOD"] == "POST" && env["PATH_INFO"].end_with?("/transitions")

    @app.call(env).last.then { it.close if it.respond_to?(:close) } if mode == :after_app
    env["rack.hijack"].call.close
    [ 200, {}, [] ] # ignored by the server once the connection is hijacked
  end
end

RSpec.configure do |config|
  config.before(:each, type: :system) { Capybara.app = DropResponse.wrap(Capybara.app) }
  config.after(:each, type: :system) { DropResponse.mode = nil }
end
