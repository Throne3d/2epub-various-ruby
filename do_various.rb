#!/usr/bin/env ruby
require 'fileutils'
require 'pathname'
require 'logger'
require 'nokogiri'
require 'json'
require 'uri'
require 'open-uri'
require 'openssl'
require 'cgi'
require 'date'

$LOAD_PATH << '.'
require 'models'
require 'model_methods'
require 'handlers_indexes'
require 'handlers_sites'
require 'handlers_outputs'
include GlowficEpubMethods
include GlowficEpub

FileUtils.mkdir "web_cache" unless File.directory?("web_cache")
FileUtils.mkdir "logs" unless File.directory?("logs")

def main(args)
  abort "Please input an argument (e.g. 'tocs_sandbox', 'get_sandbox', 'process_sandbox', 'output_sandbox')" unless args and args.size > 0
  
  option = if args.is_a?(String)
    args.downcase.strip 
  elsif args.is_a?(Array)
    args.join(" ").downcase.strip
  else
    raise ArgumentError("process", "Invalid 'args' passed.")
  end
  process = :""
  group = :""
  
  processes = {tocs: :tocs, toc: :tocs, get: :get, epub: :epub, det: :details, process: :process, clean: :clean, rem: :remove, stat: :stats, :"do" => :"do", output_epub: :output_epub}
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
  
  if (process == :"do")
    main("tocs_#{group}")
    main("get_#{group}")
    main("process_#{group}")
  elsif (process == :tocs)
    chapter_list = GlowficEpub::Chapters.new(group: group)
    
    (LOG.fatal "Group #{group} has no TOC" and abort) unless FIC_TOCS.has_key? group and not FIC_TOCS[group].empty?
    fic_toc_url = FIC_TOCS[group]
    
    LOG.info "Parsing TOC (of #{group})"
    
    oldify_chapters_data(group)
    data = get_chapters_data(group, trash_messages: true)
    set_chapters_data(data, group)
    
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
  elsif (process == :get)
    chapter_list = get_chapters_data(group, trash_messages: true)
    (LOG.fatal "No chapters for #{group} - run TOC first" and abort) if chapter_list.nil? or chapter_list.empty?
    LOG.info "Getting '#{group}'"
    LOG.info "Chapter count: #{chapter_list.length}"
    
    unhandled_chapters = []
    instance_handlers = {}
    chapter_list.each do |chapter|
      site_handler = GlowficSiteHandlers.get_handler_for(chapter)
      
      if site_handler.nil? or (site_handler.is_a?(Array) and site_handler.empty?) or (site_handler.is_a?(Array) and site_handler.length > 1)
        LOG.error "ERROR: No site handler for #{chapter.title}!" if site_handler.nil? or (site_handler.is_a?(Array) and site_handler.empty?)
        LOG.error "ERROR: Too many site handlers for #{chapter.title}! [#{group_handler * ', '}]" if (site_handler.is_a?(Array) and site_handler.length > 1)
        unhandled_chapters << chapter
        next
      end
      
      instance_handlers[site_handler] = site_handler.new(group: group, chapters: chapter_list) unless instance_handlers.key?(site_handler)
      handler = instance_handlers[site_handler]
      
      handler.get_updated(chapter, notify: true)
      
      set_chapters_data(chapter_list, group)
    end
  elsif (process == :process)
    GlowficEpub::build_moieties
    chapter_list = get_chapters_data(group, trash_messages: true)
    (LOG.fatal "No chapters for #{group} - run TOC first" and abort) if chapter_list.nil? or chapter_list.empty?
    LOG.info "Processing '#{group}'"
    LOG.info "Chapter count: #{chapter_list.length}"
    
    site_handlers = GlowficSiteHandlers.constants.map {|c| GlowficSiteHandlers.const_get(c) }
    site_handlers.select! {|c| c.is_a? Class and c < GlowficSiteHandlers::SiteHandler }
    
    instance_handlers = {}
    chapter_list.each do |chapter|
      site_handler = site_handlers.select {|c| c.handles? chapter}
      
      if site_handler.nil? or site_handler.empty? or site_handler.length > 1
        LOG.error "ERROR: No site handler for #{chapter.title}!" if site_handler.nil? or site_handler.empty?
        LOG.error "ERROR: Too many site handlers for #{chapter.title}! [#{group_handler * ', '}]" if site_handler.length > 1
        next
      end
      
      if chapter.pages.nil? or chapter.pages.empty?
        LOG.error "No pages for #{chapter.title}!"
        next
      end
      
      site_handler = site_handler.first
      instance_handlers[site_handler] = site_handler.new(group: group, chapters: chapter_list) unless instance_handlers.key?(site_handler)
      handler = instance_handlers[site_handler]
      
      handler.get_replies(chapter, notify: true)
      
      set_chapters_data(chapter_list, group)
    end
  elsif (process == :output_epub)
    GlowficEpub::build_moieties
    chapter_list = get_chapters_data(group)
    (LOG.fatal "No chapters for #{group} - run TOC first" and abort) if chapter_list.nil? or chapter_list.empty?
    LOG.info "Processing '#{group}'"
    
    handler = GlowficOutputHandlers::EpubHandler
    handler = handler.new(chapter_list: chapter_list, group: group)
    handler.output
  elsif (process == :stats)
    GlowficEpub::build_moieties
    chapter_list = get_chapters_data(group)
    (LOG.fatal "No chapters for #{group} - run TOC first" and abort) if chapter_list.nil? or chapter_list.empty?
    LOG.info "Processing '#{group}'"
    
    #replies by author, replies by character, icon uses
    #total and per-month?
    #maybe track per continuity thing on the constellation, too.
    #things started by author
    
    stats = {}
    stats[:_] = {entry_moiety: {}, msg_moiety: {}, msg_character: {}, msg_icons: {}}
    
    chapter_list.each do |chapter|
      next unless chapter.entry
      
      msgs = [chapter.entry] + chapter.replies
      LOG.info "Processing chapter #{chapter}: #{msgs.length} message#{('s' unless msgs.length == 1)}"
      msgs.each do |msg|
        msg_date = msg.time
        msg_mo_str = "#{msg_date.year}-#{msg_date.month}"
        
        stats[msg_mo_str] = {entry_moiety: {}, msg_moiety: {}, msg_character: {}, msg_icons: {}} unless stats[msg_mo_str]
        
        msg_moiety = msg.author.moiety
        msg_char = msg.author.to_s
        msg_icon = msg.face.try(:to_s)
        
        if msg.post_type == PostType::ENTRY 
          stats[msg_mo_str][:entry_moiety][msg_moiety] = 0 unless stats[msg_mo_str][:entry_moiety].key?(msg_moiety)
          stats[msg_mo_str][:entry_moiety][msg_moiety] += 1
          stats[:_][:entry_moiety][msg_moiety] = 0 unless stats[:_][:entry_moiety].key?(msg_moiety)
          stats[:_][:entry_moiety][msg_moiety] += 1
        end
        
        stats[msg_mo_str][:msg_moiety][msg_moiety] = 0 unless stats[msg_mo_str][:msg_moiety].key?(msg_moiety)
        stats[msg_mo_str][:msg_moiety][msg_moiety] += 1
        stats[:_][:msg_moiety][msg_moiety] = 0 unless stats[:_][:msg_moiety].key?(msg_moiety)
        stats[:_][:msg_moiety][msg_moiety] += 1
        
        stats[msg_mo_str][:msg_character][msg_char] = 0 unless stats[msg_mo_str][:msg_character].key?(msg_char)
        stats[msg_mo_str][:msg_character][msg_char] += 1
        stats[:_][:msg_character][msg_char] = 0 unless stats[:_][:msg_character].key?(msg_char)
        stats[:_][:msg_character][msg_char] += 1
        
        if msg_icon
          stats[msg_mo_str][:msg_icons][msg_icon] = 0 unless stats[msg_mo_str][:msg_icons].key?(msg_icon)
          stats[msg_mo_str][:msg_icons][msg_icon] += 1
          stats[:_][:msg_icons][msg_icon] = 0 unless stats[:_][:msg_icons].key?(msg_icon)
          stats[:_][:msg_icons][msg_icon] += 1
        end
      end
      
    end
    
    p stats
  else
    LOG.info "Not yet implemented."
  end
end

if __FILE__ == $0
  main(ARGV)
end
