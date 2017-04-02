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
  |event, _file, _line, _id, _binding, _classname|
  if event == "call" && caller_locations.length > 500
    fail "stack level too deep"
  end
}

class Array
  def contains_all? other
    other = other.dup
    each {|e| i = other.index(e); if i then other.delete_at(i) end }
    other.empty?
  end
  def delete_once(value)
    i = index(value)
    delete_at(i) if i
  end
  def delete_once_if(&block)
    delete_once(detect(&block))
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

Groups:
#{FIC_NAME_MAPPING.map{|i,_| "- " + i.to_s} * "\n"}
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
    arg_val =
      if argname_bit['=']
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

PROCESSES = {
  tocs: [:toc, :tocs],
  trash: [:trash],
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

# Parses a list of arguments into an option structure.
def parse_args(args)
  args = [args] if args.is_a?(String)
  usage("Invalid arguments.") unless args && args.is_a?(Array) && args.size > 0

  options = OpenStruct.new(process: nil, group: nil, chapter_list: nil)
  options.chapter_list = args.find {|thing| thing.is_a?(Chapters)}
  args.delete(options.chapter_list) if options.chapter_list

  args = args.map(&:to_s).map(&:downcase)

  process_arg = get_arg(args, '-p', '--process', nil) || get_unguarded_arg(args)
  if process_arg
    process_sym = process_arg.to_s.downcase.strip.to_sym
    options.process = PROCESSES.detect do |_, match_list|
      match_list.index(process_sym)
    end.try(:first)
  end


  group_arg = get_arg(args, '-g', '--group', nil) || get_unguarded_arg(args)
  if group_arg
    group_sym = group_arg.to_s.downcase.strip.to_sym
    options.group = FIC_NAME_MAPPING.detect do |_, match_list|
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
    chapter_list.old_characters = nil
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

  if [:"do", :epubdo, :repdo].include?(process)
    chapter_list = main('tocs', group)
    chapter_list = main('qget', group, chapter_list)

    processmethods = {:"do" => 'process', epubdo: 'qprocess', repdo: 'report'}
    processmethod = processmethods[process]
    chapter_list = main(processmethod, group, chapter_list)

    if process == :epubdo
      chapter_list = main('output_epub', group, chapter_list)
    elsif process == :repdo
      chapter_list = main('output_report', group, chapter_list)
    end
    return chapter_list
  elsif (process == :trash)
    LOG.info "Trashing (oldifying) #{group}"

    oldify_chapters_data(group)
    data = get_chapters_data(group, trash_messages: true)
    data.each { |chapter| chapter.processed = false }
    set_chapters_data(data, group)
    LOG.info "Done."
    return data
  end

  if (process == :tocs)
    chapter_list ||= GlowficEpub::Chapters.new(group: group)

    fic_toc_url = FIC_TOCS[group]
    (LOG.fatal "Group #{group} has no TOC"; abort) unless fic_toc_url.present?

    LOG.info "Parsing TOC (of #{group})"

    oldify_chapters_data(group)
    data = get_old_data(group)
    chapter_list.old_characters = data.characters
    chapter_list.old_faces = data.faces

    group_handler = GlowficIndexHandlers.get_handler_for(group)
    (LOG.fatal "No index handlers for #{group}!"; abort) if group_handler.nil?
    (LOG.fatal "Too many index handlers for #{group}! [#{group_handler * ', '}]"; abort) if group_handler.is_a?(Array) && group_handler.length > 1

    handler = group_handler.new(group: group, chapter_list: chapter_list, old_chapter_list: data)
    chapter_list = handler.toc_to_chapterlist(fic_toc_url: fic_toc_url) do |chapter|
      LOG.info chapter.to_s
    end
    set_chapters_data(chapter_list, group)
    clear_old_data
    return chapter_list
  end

  chapter_list ||= get_chapters_data(group)
  (LOG.fatal "No chapters for #{group} - run TOC first"; abort) if chapter_list.nil? || chapter_list.empty?

  if (process == :get || process == :qget || process == :process || process == :qprocess || process == :report)
    process_type = (process == :get || process == :qget) ? :get : :process
    process_save = (process == :qget || process == :qprocess || process == :report) ? :quick : :normal

    LOG.info "#{(process_type == :get) ? 'Getting' : 'Processing'} '#{group}'" + (process == :report ? ' (daily report)' : '') + (process_save == :quick ? ' (quick)' : '')
    LOG.info "Chapter count: #{chapter_list.length}"

    instance_handlers = {}
    chapter_count = chapter_list.length
    unhandled_chapters = []
    has_changed = false
    diff = true
    begin
      chapter_list.each_with_index do |chapter, i|
        site_handler = GlowficSiteHandlers.get_handler_for(chapter)

        if site_handler.nil? || (site_handler.is_a?(Array) && site_handler.length != 1)
          LOG.error "ERROR: No site handler for #{chapter.title}!" if site_handler.nil? || site_handler.empty?
          LOG.error "ERROR: Too many site handlers for #{chapter.title}! [#{site_handler * ', '}]" if !site_handler.nil? && site_handler.length > 1
          unhandled_chapters << chapter
          next
        end

        instance_handlers[site_handler] ||= site_handler.new(group: group, chapters: chapter_list)
        handler = instance_handlers[site_handler]

        if process_type == :process
          if chapter.pages.blank?
            LOG.error "No pages for #{chapter.title}!"
            next
          end

          diff = true
          only_attrs = (process == :report ? [:time, :edittime] : nil)
          handler.get_replies(chapter, notify: true, only_attrs: only_attrs) do |msg|
            LOG.info "(#{i+1}/#{chapter_count}) " + msg
            diff = false if msg[": unchanged, cached"]
          end
        else
          diff = false
          handler.get_updated(chapter, notify: true) do |msg|
            LOG.info "(#{i+1}/#{chapter_count}) " + msg
            diff = msg.start_with?('New') || msg.start_with?('Updated')
          end
        end

        has_changed = true if diff

        set_chapters_data(chapter_list, group) if diff && process_save != :quick
      end
    rescue StandardError, Interrupt => e
      if process_save == :quick && has_changed
        puts "Encountered an error. Saving changed data then re-raising."
        set_chapters_data(chapter_list, group)
      end
      raise e
    end
    set_chapters_data(chapter_list, group) if process_save == :quick || !diff
  elsif (process == :output_epub || process == :output_html)
    LOG.info "Outputting #{process == :output_epub ? 'an EPUB for' : 'an HTML copy of'} '#{group}'"

    no_split = option[/no[_\s\-]split/]

    handler = GlowficOutputHandlers::EpubHandler
    mode = process.to_s.sub('output_','').to_sym
    params = {chapter_list: chapter_list, group: group, mode: mode}
    params[:no_split] = true if no_split

    handler = handler.new(params)
    changed = handler.output
    set_chapters_data(chapter_list, group) if changed
  elsif (process == :output_report)
    LOG.info "Outputting a report for '#{group}'"

    params = {}

    date_bit = option[/(\d+)((-|\s)?\d+)?{2}/]
    if date_bit
      date_bits = date_bit.split(/(?:-|\s)+/)
      day = date_bits.last.to_i
      month = date_bits[-2].to_i
      year = (date_bits.length > 2 ? date_bits[-3].to_i : DateTime.now.year)

      params[:date] = Date.new(year, month, day)
      option = option.sub(date_bit, '').strip
    end

    early_bit = option[/(show)?[_\-\s]?earl(y|ier)/]
    if early_bit
      params[:show_earlier] = true
      option = option.sub(early_bit, '').strip
    end

    # TODO: "number" (number of posts in the past day) or whatever as an option

    handler = GlowficOutputHandlers::ReportHandler
    handler = handler.new(chapter_list: chapter_list, group: group)
    handler.output(params)
  elsif (process == :output_rails)
    LOG.info "Outputting Rails stuff for '#{group}'"

    handler = GlowficOutputHandlers::RailsHandler
    handler = handler.new(chapter_list: chapter_list, group: group)
    handler.output
  elsif (process == :stats)
    LOG.info "Doing stats for '#{group}'"

    # list:
    # replies by author (moiety), character, icon uses; posts by …
    # total and per-month?
    # maybe track per continuity

    blank_hash = Hash.new { Hash.new(0) }
    # entry_moiety:, msg_moiety:, msg_character:, msg_icons:, moiety_words:, char_words:, icons_words:
    stats = {}
    stats[:_] = blank_hash.clone

    html_match = Regexp.compile(/\<[^\>]*?\>/)
    word_match = Regexp.compile(/[\w']+/)

    chapter_urls = []

    chapter_list.each do |chapter|
      next unless chapter.entry
      (LOG.info "Skipping duplicate: #{chapter}"; next) if chapter_urls.include?(chapter.url)
      chapter_urls << chapter.url

      msgs = [chapter.entry] + chapter.replies
      LOG.info "Processing chapter #{chapter}: #{msgs.length} message#{('s' unless msgs.length == 1)}"

      msgs.each do |msg|
        msg_date = msg.time
        msg_mo_str = "#{msg_date.year}-#{msg_date.month}"

        stats[msg_mo_str] ||= blank_hash.clone

        msg_moiety = msg.moiety
        msg_char = msg.character.to_s
        msg_icon = msg.face.try(:to_s)

        msg_text = msg.content.gsub(html_match, ' ')
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
  end

  return chapter_list
end

if __FILE__ == $0
  main(ARGV)
end
