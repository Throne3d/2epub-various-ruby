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
require 'handlers_chapters'
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
GROUP_HANDLERS = {glowfic: GlowficChapterHandlers::CommunityHandler, effulgence: GlowficChapterHandlers::OrderedListHandler, pixiethreads: GlowficChapterHandlers::OrderedListHandler, incandescence: GlowficChapterHandlers::OrderedListHandler, radon: GlowficChapterHandlers::OrderedListHandler, sandbox: GlowficChapterHandlers::SandboxListHandler, marri: GlowficChapterHandlers::NeatListHandler, peterverse: GlowficChapterHandlers::NeatListHandler, maggie: GlowficChapterHandlers::NeatListHandler}
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
class Object
  def try(*params, &block)
    if params.empty? && block_given?
      yield self
    else
      public_send(*params, &block) if respond_to? params.first
    end
  end
end

def make_chapter(options={})
  chapter = GlowficEpub::Chapter.new(options)
  LOG.info chapter.to_s
end

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
    
    abort "Group #{group} has no TOC" unless FIC_TOCS.has_key? group and not FIC_TOCS[group].empty?
    fic_toc_url = FIC_TOCS[group]
    
    LOG.info "Parsing TOC (of #{group})"
    
    prev_chapter_data = get_chapters_data(group)
    set_chapters_data(prev_chapter_data, group, old: true) unless prev_chapter_data.empty?
    
    abort "Couldn't find a handler for group '#{group}'." unless GROUP_HANDLERS.key?(group)
    group_handler = GROUP_HANDLERS[group].new(group: group)
    chapter_list = group_handler.toc_to_chapterlist(fic_toc_url: fic_toc_url) do |chapter|
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
