#!/usr/bin/env ruby
require 'rubygems'
require 'bundler/setup'
require 'logger'
require 'date'
require 'active_support'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/object/try'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/string'
require 'active_support/time_with_zone'
require 'active_support/json'
require 'oj'
require 'pry'

Oj.default_options = {:mode => :compat}

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

set_trace_func proc {
  |event, file, line, id, binding, classname|
  if event == "call" && caller_locations.length > 500
    fail "stack level too deep"
  end
}

class Array
  def contains_all? other
    other = other.dup
    each {|e| if i = other.index(e) then other.delete_at(i) end }
    other.empty?
  end
end

def main(*args)
  abort "Please input an argument (e.g. 'tocs_sandbox', 'get_sandbox', 'process_sandbox', 'output_sandbox')" unless args and args.size > 0
  args = args.first if args.length <= 1

  chapter_list = nil
  if args.is_a?(String)
    option = args.downcase.strip
  elsif args.is_a?(Array)
    chapter_list = args.find {|thing| thing.is_a?(Chapters)}
    args.delete(chapter_list) if chapter_list
    option = args.join(' ').downcase.strip
  else
    raise ArgumentError("args", "Invalid 'args' passed.")
  end
  process = :""
  group = :""

  if chapter_list
    chapter_list.old_authors = nil
    chapter_list.old_faces = nil
  end

  process_thing = nil
  processes = {toc: :tocs, tocs: :tocs, update_toc: :update_toc, qget: :qget, get: :get, epub: :epub, det: :details, detail: :details, details: :details, process: :process, qprocess: :qprocess, clean: :clean, rem: :remove, remove: :remove, stat: :stats, stats: :stats, :"do" => :"do", epubdo: :epubdo, repdo: :repdo, output_epub: :output_epub, output_html: :output_html, report: :report, output_report: :output_report, output_rails: :output_rails, test1: :test1, test2: :test2, trash: :trash}
  # put these in order of "shortest match" to "longest match", so "toc" before "tocs" (larger match later, subsets before)
  processes.each do |key, value|
    if (option[0, key.length].to_sym == key || option[0, key.length].gsub(' ', '_').to_sym == key)
      process = value
      process_thing = option[0, key.length]
    end
  end

  abort "Unknown option. Please try with a valid option (call with no parameters to see some examples)." if process.empty?

  option = if option[process_thing.to_s]
    option.sub(process_thing.to_s, '')
  elsif option[process_thing2 = process_thing.to_s.gsub('_', ' ')]
    option.sub(process_thing2, '')
  else
    LOG.error "process '#{process_thing.to_s}' could not be found in option: #{option}"
    option
  end.strip.sub(/^\_/, '')

  group_thing = nil
  showAuthors = false
  unless process == :remove
    group = nil
    FIC_NAME_MAPPING.each do |key, findArr|
      findArr.each do |findSym|
        if (option[0, findSym.length].to_sym == findSym || option[0, findSym.length].gsub(' ', '_').to_sym == findSym)
          group = key
          group_thing = option[0, findSym.length]
        end
      end
    end
    abort "Unknown thing to download. Please try with a valid option (call with no parameters to see some examples)." unless group

    showAuthors = FIC_SHOW_AUTHORS.include? group
  end

  option = option.sub(group_thing.to_s, '').sub(group_thing.to_s.gsub('_', ' '), '').strip.sub(/^\_/, '')

  OUTFILE.set_output_params(process, (group.empty? ? nil : group))

  LOG.info "Option: #{option}"
  LOG.info "Process: #{process}"
  LOG.info "Group: #{group}"
  LOG.info "Other params: #{option}" if option.present?

  LOG.info "-" * 60

  if (process == :"do")
    chapter_list = main("tocs_#{group}")
    chapter_list = main("get_#{group}", chapter_list)
    chapter_list = main("process_#{group}", chapter_list)
  elsif (process == :epubdo)
    chapter_list = main("tocs_#{group}")
    chapter_list = main("qget_#{group}", chapter_list)
    chapter_list = main("qprocess_#{group}", chapter_list)
    main("output_epub_#{group}", chapter_list)
  elsif (process == :repdo)
    chapter_list = main("tocs_#{group}")
    chapter_list = main("qget_#{group}", chapter_list)
    chapter_list = main("report_#{group}", chapter_list)
    main("output_report_#{group}", chapter_list)
  elsif (process == :trash)
    LOG.info "Trashing (oldifying) #{group}"

    oldify_chapters_data(group)
    data = get_chapters_data(group, trash_messages: true)
    data.each { |chapter| chapter.processed = false }
    set_chapters_data(data, group)
    LOG.info "Done."
    return data
  elsif (process == :tocs)
    chapter_list ||= GlowficEpub::Chapters.new(group: group)

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

    handler = group_handler.new(group: group, chapter_list: chapter_list, old_chapter_list: data)
    chapter_list = handler.toc_to_chapterlist(fic_toc_url: fic_toc_url) do |chapter|
      LOG.info chapter.to_s
    end
    set_chapters_data(chapter_list, group)
    clear_old_data
    return chapter_list
  elsif (process == :update_toc)
    old_data = get_chapters_data(group)

    chapter_list ||= GlowficEpub::Chapters.new(group: group)
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
    return chapter_list
  elsif (process == :get || process == :qget)
    chapter_list ||= get_chapters_data(group)
    (LOG.fatal "No chapters for #{group} - run TOC first" and abort) if chapter_list.nil? or chapter_list.empty?
    LOG.info "Getting '#{group}'"
    LOG.info "Chapter count: #{chapter_list.length}"

    unhandled_chapters = []
    instance_handlers = {}
    chapter_count = chapter_list.count
    has_changed = false
    diff = true
    begin
      chapter_list.each_with_index do |chapter, i|
        site_handler = GlowficSiteHandlers.get_handler_for(chapter)

        if site_handler.nil? or (site_handler.is_a?(Array) and site_handler.empty?) or (site_handler.is_a?(Array) and site_handler.length > 1)
          LOG.error "ERROR: No site handler for #{chapter.title}!" if site_handler.nil? or (site_handler.is_a?(Array) and site_handler.empty?)
          LOG.error "ERROR: Too many site handlers for #{chapter.title}! [#{site_handler * ', '}]" if (site_handler.is_a?(Array) and site_handler.length > 1)
          unhandled_chapters << chapter
          next
        end

        instance_handlers[site_handler] = site_handler.new(group: group, chapters: chapter_list) unless instance_handlers.key?(site_handler)
        handler = instance_handlers[site_handler]

        diff = false
        handler.get_updated(chapter, notify: true) do |msg|
          LOG.info "(#{i+1}/#{chapter_count}) " + msg
          diff = msg.start_with?('New') || msg.start_with?('Updated')
        end
        has_changed = true if diff

        set_chapters_data(chapter_list, group) if diff && process != :qget
      end
    rescue StandardError, Interrupt => e
      if process == :qget && has_changed
        puts "Encountered an error. Saving changed data then re-raising."
        set_chapters_data(chapter_list, group)
      end
      raise e
    end
    set_chapters_data(chapter_list, group) if process == :qget or !diff
    return chapter_list
  elsif (process == :process || process == :qprocess || process == :report)
    chapter_list ||= get_chapters_data(group)
    (LOG.fatal "No chapters for #{group} - run TOC first" and abort) if chapter_list.nil? or chapter_list.empty?
    LOG.info "Processing '#{group}'" + (process == :report ? " (daily report)" : "")
    LOG.info "Chapter count: #{chapter_list.length}"

    site_handlers = GlowficSiteHandlers.constants.map {|c| GlowficSiteHandlers.const_get(c) }
    site_handlers.select! {|c| c.is_a? Class and c < GlowficSiteHandlers::SiteHandler }

    instance_handlers = {}
    chapter_count = chapter_list.count
    begin
      chapter_list.each_with_index do |chapter, i|
        diff = true
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

        diff = true
        handler.get_replies(chapter, notify: true, only_attrs: only_attrs) do |msg|
          LOG.info "(#{i+1}/#{chapter_count}) " + msg
          diff = false if msg[": unchanged, cached"]
        end

        set_chapters_data(chapter_list, group) if diff && process != :report && process != :qprocess
      end
    rescue StandardError, Interrupt => e
      if process == :report || process == :qprocess
        puts "Encountered an error. Saving changed data then re-raising."
        set_chapters_data(chapter_list, group)
      end
      raise e
    end
    set_chapters_data(chapter_list, group) if process == :report || process == :qprocess || !diff
    return chapter_list
  elsif (process == :output_epub || process == :output_html)
    chapter_list ||= get_chapters_data(group)
    (LOG.fatal "No chapters for #{group} - run TOC first" and abort) if chapter_list.nil? or chapter_list.empty?
    LOG.info "Outputting an EPUB for '#{group}'" if process == :output_epub
    LOG.info "Outputting an HTML copy of '#{group}'" if process == :output_html
    (LOG.fatal "Invalid output mode #{process}" and abort) unless process == :output_epub or process == :output_html

    no_split = option[/no[_\s\-]split/]

    handler = GlowficOutputHandlers::EpubHandler
    mode = (process == :output_epub ? :epub : process == :output_html ? :html : :unknown)
    params = {chapter_list: chapter_list, group: group, mode: mode}
    params[:no_split] = true if no_split
    handler = handler.new(params)
    changed = handler.output
    set_chapters_data(chapter_list, group) if changed
  elsif (process == :output_report)
    chapter_list ||= get_chapters_data(group)
    (LOG.fatal "No chapters for #{group} - run TOC first" and abort) if chapter_list.nil? or chapter_list.empty?
    LOG.info "Outputting a report for '#{group}'"

    params = {}

    if date_bit = option[/(\d+)((-|\s)?\d+)?{2}/]
      date_bits = date_bit.split(/(-|\s)/)
      day = date_bits.last.to_i
      month = date_bits[date_bits.length-2].to_i
      year = (date_bits.length > 2 ? date_bits[date_bits.length-3].to_i : DateTime.now.year)

      params[:date] = Date.new(year, month, day)
      option = option.sub(date_bit, '').strip
    end

    if early_bit = option[/(show)?[_\-\s]?earl(y|ier)/]
      params[:show_earlier] = true
      option = option.sub(early_bit, '').strip
    end

    # TODO: "number" (number of posts in the past day) or whatever as an option

    handler = GlowficOutputHandlers::ReportHandler
    handler = handler.new(chapter_list: chapter_list, group: group)
    handler.output(params)
  elsif (process == :output_rails)
    chapter_list ||= get_chapters_data(group)
    (LOG.fatal "No chapters for #{group} - run TOC first" and abort) if chapter_list.nil? or chapter_list.empty?
    LOG.info "Outputting Rails stuff for '#{group}'"

    handler = GlowficOutputHandlers::RailsHandler
    handler = handler.new(chapter_list: chapter_list, group: group)
    handler.output
  elsif (process == :test1)
    chapter_list = get_chapters_data(group)
  elsif (process == :test2)
    chapter_list = get_chapters_data(group)
    5.times { set_chapters_data(chapter_list, group) }
  elsif (process == :stats)
    chapter_list ||= get_chapters_data(group)
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
