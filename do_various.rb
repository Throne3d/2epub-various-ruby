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
require 'ostruct'

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
  def delete_once_if(&block)
    delete(detect(&block))
  end
end

def usage(s=nil)
  usage_str = <<HEREDOC
Usage: #{File.basename($0)}: <process> <group> [extras]

Combined processes:
- do                  Executes tocs, get and process
- repdo               Executes tocs, qget, report and output_report
- epubdo              Executes tocs, qget, qprocess and output_epub

Individual processes:
- trash               Flag the scraped data as 'old'
- tocs                Scrape the table of contents
- get                 Download the pages to scrape
- process             Scrape the downloaded pages
- output_epub         Output an EPUB of the scraped data
- output_html         Output the HTML archive of the scraped data
- output_report       Output the BB-code for the report for the scraped data
- output_rails        Output the scraped data to a local copy of the Constellation
- stats               Output data on word counts by various groupings

- update_toc          (deprecated) Update the data with the new ToC

Groups:
#{FIC_NAME_MAPPING.map{|i,j| "- " + i.to_s} * "\n"}
HEREDOC

  if __FILE__ == $0
    $stderr.puts s unless s.nil?
    $stderr.puts usage_str
    abort
  else
    raise ArgumentError("args", s || "Invalid args passed.")
  end
end

# Returns the value from args for the appropriate shortarg or longarg
# Defaults to default
# examples:
# get_arg(['-p', 'value'], '-p', '--process') #=> 'value'
# get_arg(['--process', 'value'], '-p', '--process') #=> 'value'
# get_arg(['--test', 'value'], '-p', '--process') #=> nil
# get_arg(['--test', 'value'], '-p', '--process', false) #=> false
# Removes the appropriate shortarg/longarg & value pair from the array.
def get_arg(args, shortarg, longarg, default=nil)
  argname_bit = args.detect{|arg| (!shortarg.nil? && arg.start_with?(shortarg)) || arg =~ /^#{Regexp.escape(longarg)}\b/}
  arg_val = nil
  if argname_bit
    arg_index = args.index(argname_bit)
    arg_val = if argname_bit['=']
      argname_bit.split('=',2).last
    elsif argname_bit[' ']
      argname_bit.split(' ',2).last
    else
      temp_val = args[arg_index+1]
      if temp_val.nil? || !temp_val.start_with?('-')
        # if the value is nil, or it's not another argument
        args.delete_at(arg_index+1)
      else
        # if it's another argument
        true
      end
    end
    args.delete_at(arg_index)
  end
  # LOG.debug "get_arg got #{arg_val.inspect} for #{shortarg}, #{longarg}, default: #{default}"
  return arg_val || default
end

# Returns the first argument from args that isn't guarded by a flag (short or long)
# Defaults to default
# examples:
# get_unguarded_arg(['-p', 'test', 'thing']) #=> 'thing'
# get_unguarded_arg(['-p', 'test']) #=> nil
# get_unguarded_arg(['-p', 'test'], false) #=> false
# get_unguarded_arg(['val', '-p', 'test']) #=> 'val'
# get_unguarded_arg(['--process=test', 'val']) #=> 'val'
def get_unguarded_arg(args, default=nil)
  guarded = false
  arg = args.delete_once_if do |i|
    (guarded = false; next) if guarded
    if i =~ /^--?[\w\-]+/
      (guarded = true; next) unless i['='] || i[' ']
    end
    !guarded
  end
  # LOG.debug "get_unguarded_arg got #{arg.inspect}"
  # finds the first parameter that's not an argument, or that's not
  # directly after an argument that lacks "=" and " ".
  arg || default
end

# Parses a list of arguments into an option structure.
def parse_args(args)
  args = [args] if args.is_a?(String)
  usage("Invalid arguments.") unless args && args.is_a?(Array) && args.size > 0

  options = OpenStruct.new(process: nil, group: nil, chapter_list: nil)
  options.chapter_list = args.find {|thing| thing.is_a?(Chapters)}
  args.delete(options.chapter_list) if options.chapter_list

  args = args.map(&:to_s).map(&:downcase)

  processes = {
    tocs: [:toc, :tocs],
    trash: [:trash],
    update_toc: [:update_toc], # deprecated?
    qget: [:qget],
    get: [:get],
    process: [:process],
    qprocess: [:qprocess],
    report: [:report],
    output_epub: [:epub, :output_epub],
    output_html: [:output_html],
    output_report: [:output_report],
    output_rails: [:output_rails],
    stats: [:stat, :stats],
    :"do" => [:"do"],
    epubdo: [:epubdo],
    repdo: [:repdo],
    test1: [:test1],
    test2: [:test2]
    # details: [:detail, :details],
  }

  process_arg = get_arg(args, '-p', '--process', nil) || get_unguarded_arg(args)
  if process_arg
    process_sym = process_arg.to_s.downcase.strip.to_sym
    options.process = processes.detect do |key, match_list|
      match_list.index(process_sym)
    end.try(:first)
  end


  group_arg = get_arg(args, '-g', '--group', nil) || get_unguarded_arg(args)
  if group_arg
    group_sym = group_arg.to_s.downcase.strip.to_sym
    options.group = FIC_NAME_MAPPING.detect do |key, match_list|
      match_list.index(group_sym)
    end.try(:first)
  end


  options.extras = args

  usage("You must provide both a process and a group.") unless options.process && options.group
  options
end

def main(*args)
  args = args.first if args.is_a?(Array) && args.first.is_a?(Array)
  options = parse_args(args)

  chapter_list = options.chapter_list
  if chapter_list
    chapter_list.old_authors = nil
    chapter_list.old_faces = nil
  end

  process = options.process
  group = options.group

  option = options.extras.join(' ').downcase

  OUTFILE.set_output_params(process, (group.empty? ? nil : group))

  LOG.info "Option: #{option}"
  LOG.info "Process: #{process}"
  LOG.info "Group: #{group}"
  LOG.info "Other params: #{option}" if option.present?

  LOG.info "-" * 60

  if (process == :"do")
    chapter_list = main('tocs', group)
    chapter_list = main('get', group, chapter_list)
    chapter_list = main('process', group, chapter_list)
  elsif (process == :epubdo)
    chapter_list = main('tocs', group)
    chapter_list = main('qget', group, chapter_list)
    chapter_list = main('qprocess', group, chapter_list)
    main('output_epub', group, chapter_list)
  elsif (process == :repdo)
    chapter_list = main('tocs', group)
    chapter_list = main('qget', group, chapter_list)
    chapter_list = main('report', group, chapter_list)
    main('output_report', group, chapter_list)
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
    params = {}

    if date_bit = option[/(\d+)((-|\s)?\d+)?{2}/]
      date_bits = date_bit.split(/(?:-|\s)+/)
      day = date_bits.last.to_i
      month = date_bits[-2].to_i
      year = (date_bits.length > 2 ? date_bits[-3].to_i : DateTime.now.year)

      params[:date] = Date.new(year, month, day)
      option = option.sub(date_bit, '').strip
    end

    if early_bit = option[/(show)?[_\-\s]?earl(y|ier)/]
      params[:show_earlier] = true
      option = option.sub(early_bit, '').strip
    end

    chapter_list ||= get_chapters_data(group)
    (LOG.fatal "No chapters for #{group} - run TOC first" and abort) if chapter_list.nil? or chapter_list.empty?
    LOG.info "Outputting a report for '#{group}'"

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

    blank_hash = {entry_moiety: Hash.new(0), msg_moiety: Hash.new(0), msg_character: Hash.new(0), msg_icons: Hash.new(0), moiety_words: Hash.new(0), char_words: Hash.new(0), icons_words: Hash.new(0)}
    stats = {}
    stats[:_] = blank_hash.clone

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

        stats[msg_mo_str] = blank_hash.clone unless stats[msg_mo_str]

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
