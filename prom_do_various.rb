#!/usr/bin/env ruby
require 'memory_profiler'
$LOAD_PATH << '.'
require 'do_various'

if __FILE__ == $0
  dir = "prof-" + (ARGV.is_a?(Array) ? ARGV * '_' : ARGV).gsub(/\W+/, '_')
  FileUtils.mkdir dir unless File.directory?(dir)
  
  MemoryProfiler.report(allow_files: ['2epub-various-ruby', 'nokogiri'], top: 200) do
    begin
      main(ARGV)
    rescue StandardError, Interrupt => e
      puts "Encountered error, logging profiling to this point."
      puts e
    end
  end.pretty_print(to_file: dir + '/memory.log')
end
