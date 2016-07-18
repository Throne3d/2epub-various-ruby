#!/usr/bin/env ruby
require 'rubygems'
require 'logger'
require 'active_support'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/object/try'
require 'active_support/json'

$LOAD_PATH << '.'
$LOAD_PATH << 'script'
$LOAD_PATH << 'script/scraper'
$LOAD_PATH << File.dirname(__FILE__)
require 'models'
require 'model_methods'
require 'handlers_indexes'
require 'handlers_sites'
require 'handlers_outputs'
include GlowficEpubMethods
include GlowficEpub

FileUtils.mkdir "web_cache" unless File.directory?("web_cache")
FileUtils.mkdir "logs" unless File.directory?("logs")

class Array
  def contains_all? other
    other = other.dup
    each {|e| if i = other.index(e) then other.delete_at(i) end }
    other.empty?
  end
end

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
  
  processes = {tocs: :tocs, toc: :tocs, update_toc: :update_toc, qget: :qget, get: :get, epub: :epub, det: :details, process: :process, clean: :clean, rem: :remove, stat: :stats, :"do" => :"do", repdo: :repdo, output_epub: :output_epub, report: :report, output_report: :output_report, test1: :test1, test2: :test2, trash: :trash}
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
  elsif (process == :repdo)
    main("tocs_#{group}")
    main("qget_#{group}")
    main("report_#{group}")
    main("output_report_#{group}")
  elsif (process == :trash)
    LOG.info "Trashing (oldifying) #{group}"
    
    oldify_chapters_data(group)
    data = get_chapters_data(group, trash_messages: true)
    data.each { |chapter| chapter.processed = false }
    set_chapters_data(data, group)
    LOG.info "Done."
  elsif (process == :tocs)
    chapter_list = GlowficEpub::Chapters.new(group: group)
    
    (LOG.fatal "Group #{group} has no TOC" and abort) unless FIC_TOCS.has_key? group and not FIC_TOCS[group].empty?
    fic_toc_url = FIC_TOCS[group]
    
    LOG.info "Parsing TOC (of #{group})"
    
    oldify_chapters_data(group)
    data = get_old_data(group)
    chapter_list.old_authors = data.authors
    chapter_list.old_faces = data.faces
    
    group_handlers = GlowficIndexHandlers.constants.map {|c| GlowficIndexHandlers.const_get(c) }
    group_handlers.select! {|c| c.is_a? Class and c < GlowficIndexHandlers::IndexHandler }
    
    group_handler = group_handlers.select {|c| c.handles? group }
    (LOG.fatal "No index handlers for #{group}!" and abort) if group_handler.nil? or group_handler.empty?
    (LOG.fatal "Too many index handlers for #{group}! [#{group_handler * ', '}]" and abort) if group_handler.length > 1
    
    group_handler = group_handler.first
    
    handler = group_handler.new(group: group, chapter_list: chapter_list)
    chapter_list = handler.toc_to_chapterlist(fic_toc_url: fic_toc_url) do |chapter|
      LOG.info chapter.to_s
    end
    set_chapters_data(chapter_list, group)
  elsif (process == :update_toc)
    old_data = get_chapters_data(group)
    
    chapter_list = GlowficEpub::Chapters.new(group: group)
    (LOG.fatal "Group #{group} has no TOC" and abort) unless FIC_TOCS.has_key? group and not FIC_TOCS[group].empty?
    fic_toc_url = FIC_TOCS[group]
    
    LOG.info "Updating the data (of #{group}) with TOC data; will do stuff stupidly if there are duplicate chapters with the same URL."
    LOG.info "Parsing TOC (of #{group})"
    
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
    
    old_data.each do |chapter|
      new_count = 0
      chapter_list.each do |new_data|
        next unless new_data.url == chapter.url
        new_count += 1
        (LOG.error "-- There is a duplicate chapter! #{chapter}" and next) if new_count > 1
        
        chapter.title = new_data.title if new_data.title and not new_data.title.strip.empty?
        chapter.title_extras = new_data.title_extras if new_data.title_extras and not new_data.title_extras.strip.empty?
        chapter.thread = new_data.thread if new_data.thread
        chapter.sections = new_data.sections if new_data.sections
        chapter.time_completed = new_data.time_completed if new_data.time_completed
        chapter.report_flags = new_data.report_flags if new_data.report_flags
      end
    end
    set_chapters_data(old_data, group)
  elsif (process == :get || process == :qget)
    chapter_list = get_chapters_data(group)
    (LOG.fatal "No chapters for #{group} - run TOC first" and abort) if chapter_list.nil? or chapter_list.empty?
    LOG.info "Getting '#{group}'"
    LOG.info "Chapter count: #{chapter_list.length}"
    
    unhandled_chapters = []
    instance_handlers = {}
    chapter_list.each do |chapter|
      site_handler = GlowficSiteHandlers.get_handler_for(chapter)
      
      if site_handler.nil? or (site_handler.is_a?(Array) and site_handler.empty?) or (site_handler.is_a?(Array) and site_handler.length > 1)
        LOG.error "ERROR: No site handler for #{chapter.title}!" if site_handler.nil? or (site_handler.is_a?(Array) and site_handler.empty?)
        LOG.error "ERROR: Too many site handlers for #{chapter.title}! [#{site_handler * ', '}]" if (site_handler.is_a?(Array) and site_handler.length > 1)
        unhandled_chapters << chapter
        next
      end
      
      instance_handlers[site_handler] = site_handler.new(group: group, chapters: chapter_list) unless instance_handlers.key?(site_handler)
      handler = instance_handlers[site_handler]
      
      handler.get_updated(chapter, notify: true)
      
      set_chapters_data(chapter_list, group) unless process == :qget
    end
    set_chapters_data(chapter_list, group) if process == :qget
  elsif (process == :process or process == :report)
    chapter_list = get_chapters_data(group)
    (LOG.fatal "No chapters for #{group} - run TOC first" and abort) if chapter_list.nil? or chapter_list.empty?
    LOG.info "Processing '#{group}'" + (process == :report ? " (daily report)" : "")
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
      
      only_attrs = (process == :report ? [:time, :edittime] : nil)
      
      handler.get_replies(chapter, notify: true, only_attrs: only_attrs)
      
      set_chapters_data(chapter_list, group) unless process == :report
    end
    set_chapters_data(chapter_list, group) if process == :report
  elsif (process == :output_epub)
    chapter_list = get_chapters_data(group)
    (LOG.fatal "No chapters for #{group} - run TOC first" and abort) if chapter_list.nil? or chapter_list.empty?
    LOG.info "Outputting an EPUB for '#{group}'"
    
    handler = GlowficOutputHandlers::EpubHandler
    handler = handler.new(chapter_list: chapter_list, group: group)
    handler.output
  elsif (process == :output_report)
    date = option.sub("output_report","").sub("#{group}","")
    date = date.gsub(/[^\d]/,' ').strip
    date = nil if date.empty?
    if date
      date_bits = date.split(/\s+/)
      day = date_bits.last.to_i
      month = date_bits[date_bits.length-2].to_i
      year = (date_bits.length > 2 ? date_bits[date_bits.length-3].to_i : DateTime.now.year)
      date = Date.new(year, month, day)
    end
    
    chapter_list = get_chapters_data(group)
    (LOG.fatal "No chapters for #{group} - run TOC first" and abort) if chapter_list.nil? or chapter_list.empty?
    LOG.info "Outputting a report for '#{group}'"
    
    params = {}
    params[:date] = date if date
    handler = GlowficOutputHandlers::ReportHandler
    handler = handler.new(chapter_list: chapter_list, group: group)
    handler.output(params)
  elsif (process == :test1)
    chapter_list = get_chapters_data(group)
  elsif (process == :test2)
    chapter_list = get_chapters_data(group)
    5.times { set_chapters_data(chapter_list, group) }
  elsif (process == :stats)
    chapter_list = get_chapters_data(group)
    (LOG.fatal "No chapters for #{group} - run TOC first" and abort) if chapter_list.nil? or chapter_list.empty?
    LOG.info "Doing stats for '#{group}'"
    
    #replies by author, replies by character, icon uses
    #total and per-month?
    #maybe track per continuity thing on the constellation, too.
    #things started by author
    
    stats = {}
    stats[:_] = {entry_moiety: Hash.new(0), msg_moiety: Hash.new(0), msg_character: Hash.new(0), msg_icons: Hash.new(0), moiety_words: Hash.new(0), char_words: Hash.new(0), icons_words: Hash.new(0)}
    
    html_match = Regexp.compile(/\<[^\>]*?\>/)
    word_match = Regexp.compile(/[\w']+/)
    
    chapter_urls = []
    
    chapter_list.each do |chapter|
      next unless chapter.entry
      (LOG.info "Skipping duplicate: #{chapter}" and next) if chapter_urls.include?(chapter.url)
      chapter_urls << chapter.url
      
      msgs = [chapter.entry] + chapter.replies
      LOG.info "Processing chapter #{chapter}: #{msgs.length} message#{('s' unless msgs.length == 1)}"
      msgs.each do |msg|
        msg_date = msg.time
        msg_mo_str = "#{msg_date.year}-#{msg_date.month}"
        
        stats[msg_mo_str] = {entry_moiety: Hash.new(0), msg_moiety: Hash.new(0), msg_character: Hash.new(0), msg_icons: Hash.new(0), moiety_words: Hash.new(0), char_words: Hash.new(0), icons_words: Hash.new(0)} unless stats[msg_mo_str]
        
        msg_moiety = msg.author.moiety
        msg_char = msg.author.to_s
        msg_icon = msg.face.try(:to_s)
        
        msg_text = msg.content.gsub(html_match, " ")
        msg_wordcount = msg_text.scan(word_match).length
        
        if msg.post_type == PostType::ENTRY 
          stats[msg_mo_str][:entry_moiety][msg_moiety] += 1
          stats[:_][:entry_moiety][msg_moiety] += 1
        end
        
        stats[msg_mo_str][:msg_moiety][msg_moiety] += 1
        stats[msg_mo_str][:moiety_words][msg_moiety] += msg_wordcount
        stats[:_][:msg_moiety][msg_moiety] += 1
        stats[:_][:moiety_words][msg_moiety] += msg_wordcount
        
        stats[msg_mo_str][:msg_character][msg_char] += 1
        stats[msg_mo_str][:char_words][msg_char] += msg_wordcount
        stats[:_][:msg_character][msg_char] += 1
        stats[:_][:char_words][msg_char] += msg_wordcount
        
        if msg_icon
          stats[msg_mo_str][:msg_icons][msg_icon] += 1
          stats[msg_mo_str][:icons_words][msg_icon] += msg_wordcount
          stats[:_][:msg_icons][msg_icon] += 1
          stats[:_][:icons_words][msg_icon] += msg_wordcount
        end
      end
    end
    
    LOG.info stats.inspect
  else
    LOG.info "Not yet implemented."
  end
end

if __FILE__ == $0
  main(ARGV)
end
