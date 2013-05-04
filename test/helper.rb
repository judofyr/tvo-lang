begin
  require 'simplecov'
rescue LoadError
else
  SimpleCov.start
end

$LOAD_PATH << File.expand_path('../../lib', __FILE__)
require 'minitest/autorun'
require 'tvo'

