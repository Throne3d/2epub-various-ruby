#!/usr/bin/env ruby
require 'ruby-prof'
$LOAD_PATH << '.'
require 'do_various'

def profile_bit(args=ARGV)
  RubyProf.start
  begin
    main(ARGV)
  rescue StandardError, Interrupt => e
    yield RubyProf.stop
    raise e
  end
  yield RubyProf.stop
end

if __FILE__ == $0
  profile_bit(ARGV) do |result|
    result.eliminate_methods!([/Object#try!?/, /Integer#upto/, /Kernel#public_send/, /(ActiveSupport::)?Tryable#try!?/])
    printer = RubyProf::MultiPrinter.new(result)
    directory = "prof-" + (ARGV.is_a?(Array) ? ARGV * '_' : ARGV).gsub(/\W+/, '_')
    FileUtils.mkdir directory unless File.directory?(directory)
    printer.print(:path => directory, :profile => 'profile', :min_percent => 0.05)
  end
end
