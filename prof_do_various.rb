#!/usr/bin/env ruby
require 'ruby-prof'
$LOAD_PATH << '.'
require 'do_various'

RubyProf.start
if __FILE__ == $0
  main(ARGV)
end
result = RubyProf.stop
printer = RubyProf::MultiPrinter.new(result)
printer.print(:path => '.', :profile => 'profile', :min_percent => 0.05)
