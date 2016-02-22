require 'fileutils'
require 'pathname'
require 'logger'

LOG = Logger.new

def main(args)
    abort "Please input an argument (e.g. 'tocs_sandbox', 'flats_sandbox', 'epub_sandbox', or 'remove alicorn*#1640' to remove all 1640.html within any alicorn* community)" unless args.size > 0
    FileUtils.mkdir "web_cache" unless File.directory?("web_cache")
    
    option = args.join(" ").downcase.strip
    process = ""
    group = ""
    
    if (option[0,4] == "tocs")
        process = :tocs
    elsif (option[0,5] == "flats")
        process = :flats
    elsif (option[0,4] == "epub")
        process = :epub
    elsif (option[0,3] == "det")
        process = :details
    elsif (option[0,5] == "clean")
        process = :clean
    elsif (option[0,3] == "rem")
        process = :remove
    elsif (option[0,4] == "stat")
        process = :stats
    else
        abort "Unknown option. Please try with a valid option (call with no parameters to see some examples)."
    end
    
    showAuthors = false
    if (process != "remove")
        if (option[-10..-1] == "effulgence")
            group = :effulgence
        elsif (option[-13..-1] == "incandescence")
            group = :incandescence
        elsif (option[-7..-1] == "sandbox")
            group = :sandbox
            showAuthors = true
        elsif (option[-12..-1] == "pixiethreads")
            group = :pixiethreads
        elsif (option[-12..-1] == "othersandbox" or option[-8..-1] == "sandbox2" or option[-7..-1] == "glowfic")
            group = :glowfic
            showAuthors = true
        elsif (option[-5..-1] == "marri" or option[-11..-1] == "marrinikari")
            group = :marri
            showAuthors = true
        elsif (option[-5..-1] == "radon" or option[-8..-1] == "absinthe")
            group = :radon-absinthe
        elsif (option[-5..-1] == "peter" or option[-10..-1] == "peterverse")
            group = :peterverse
        elsif (option[-6..-1] == "maggie" or option[-15..-1] == "maggieoftheowls")
            group = :maggie
        else
            abort("Unknown thing to download. Please try with a valid option (call with no parameters to see some examples).")
        end
    end
    
    set_output_settings(process: process, group: (group != "" ? group : "remove"))
    
    puts "Option: #{option}"
    puts "Group: #{group}"
    puts "Process: #{process}"
    
    puts "-" * 20
    puts "Not yet implemented."
end

if __FILE__ == $0
    main(ARGV)
end