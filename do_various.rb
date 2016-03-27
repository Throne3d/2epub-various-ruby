#!/usr/bin/env ruby
require 'fileutils'
require 'pathname'
require 'logger'
require 'nokogiri'
require 'json'
require 'uri'
require 'open-uri'
require 'cgi'

$LOAD_PATH << '.'
require 'models'
require 'model_methods'
require 'handlers_indexes'
include GlowficEpubMethods

FileUtils.mkdir "web_cache" unless File.directory?("web_cache")
FileUtils.mkdir "logs" unless File.directory?("logs")

FIC_NAME_MAPPING = {
  effulgence: [:effulgence],
  incandescence: [:incandescence],
  sandbox: [:sandbox],
  pixiethreads: [:pixiethreads],
  glowfic: [:othersandbox, :sandbox2, :glowfic],
  marri: [:marri, :marrinikari],
  radon: [:radon, :absinthe],
  peterverse: [:peter, :pedro, :peterverse],
  maggie: [:maggie, :maggieoftheowls, :"maggie-of-the-owls"]
}
FIC_SHOW_AUTHORS = [:sandbox, :glowfic, :marri, :peterverse, :maggie]
FIC_TOCS = {
  #Sandboxes
  sandbox: "http://alicornutopia.dreamwidth.org/1640.html?style=site",
  glowfic: "http://glowfic.dreamwidth.org/2015/06/",
  
  #Continuities
  effulgence: "http://edgeofyourseat.dreamwidth.org/2121.html?style=site",
  incandescence: "http://alicornutopia.dreamwidth.org/7441.html?style=site",
  pixiethreads: "http://pixiethreads.dreamwidth.org/613.html?style=site",
  radon: "http://radon-absinthe.dreamwidth.org/295.html?style=site",
  
  #Authors
  marri: "http://marrinikari.dreamwidth.org/1634.html?style=site",
  peterverse: "http://peterverse.dreamwidth.org/1643.html?style=site",
  maggie: "http://maggie-of-the-owls.dreamwidth.org/454.html?style=site"
}

def main(args)
  abort "Please input an argument (e.g. 'tocs_sandbox', 'flats_sandbox', 'epub_sandbox', or 'remove alicorn*#1640' to remove all 1640.html within any alicorn* community)" unless args.size > 0
  
  option = args.join(" ").downcase.strip
  process = :""
  group = :""
  
  processes = {tocs: :tocs, toc: :tocs, flats: :flats, epub: :epub, det: :details, 
    clean: :clean, rem: :remove, stat: :stats}
  processes.each do |key, value|
    if (option[0, key.length].to_sym == key)
      process = value
    end
  end
  
  abort "Unknown option. Please try with a valid option (call with no parameters to see some examples)." if process.empty?
  
  showAuthors = false
  unless process == :remove
    group = nil
    FIC_NAME_MAPPING.each do |key, findArr|
      findArr.each do |findSym|
        if option.length >= findSym.length and option[-findSym.length..-1] == findSym.to_s
          group = key
        end
      end
    end
    abort "Unknown thing to download. Please try with a valid option (call with no parameters to see some examples)." unless group
    
    showAuthors = FIC_SHOW_AUTHORS.include? group
  end
  
  OUTFILE.set_output_params(process, (group.empty? ? nil : group))
  
  LOG.info "Option: #{option}"
  LOG.info "Group: #{group}"
  LOG.info "Process: #{process}"
  
  LOG.info "-" * 60
  
  if (process == :tocs)
    chapter_list = []
    
    (LOG.fatal "Group #{group} has no TOC" and abort) unless FIC_TOCS.has_key? group and not FIC_TOCS[group].empty?
    fic_toc_url = FIC_TOCS[group]
    
    LOG.info "Parsing TOC (of #{group})"
    
    prev_chapter_data = get_chapters_data(group)
    set_chapters_data(prev_chapter_data, group, old: true) unless prev_chapter_data.empty?
    
    group_handlers = GlowficIndexHandlers.constants.map {|c| GlowficIndexHandlers.const_get(c) }
    group_handlers.select! {|c| c.is_a? Class and c < GlowficIndexHandlers::IndexHandler }
    
    group_handler = group_handlers.select {|c| c.handles? group }
    (LOG.fatal "No index handlers for #{group}!" and abort) if group_handler.nil? or group_handler.empty?
    (LOG.fatal "Too many index handlers for #{group}! [#{group_handler * ', '}]" and abort) if group_handler.length > 1
    
    group_handler = group_handler.first
    
    handler = group_handler.new(group: group)
    chapter_list = handler.toc_to_chapterlist(fic_toc_url: fic_toc_url) do |chapter|
      LOG.info chapter.to_s
    end
    set_chapters_data(chapter_list, group)
  else
    LOG.info "Not yet implemented."
  end
end

if __FILE__ == $0
  main(ARGV)
end
