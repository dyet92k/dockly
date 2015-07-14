$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'rspec'
require 'dockly'
require 'pry'

Fog.mock!

Dockly::Util::Logger.disable! unless ENV['ENABLE_LOGGER'] == 'true'
Dockly.aws_region 'us-east-1'

RSpec.configure do |config|
  config.mock_with :rspec
  config.treat_symbols_as_metadata_keys_with_true_values = true
  config.tty = true
end
