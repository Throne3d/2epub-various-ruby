﻿module GlowficEpubMethods
  class FileLogIO
    def initialize(defaultFile=nil)
      @file = File.open(defaultFile, 'a+') unless defaultFile.nil?
    end
    
    def file=(filename)
      @file.close if @file
      @file = File.open(filename, 'a+')
      @file.sync = true
    end
    
    def set_output_params(process, group=nil)
      file="logs/" + Time.now.strftime("%Y-%m-%d %H %M ") + "#{process}" + (group.nil? ? "" : "_#{group}") + ".log"
    end
    
    def write(data)
      @file.write(data) if @file
    end
    
    def close
      @file.close if @file
    end
  end

  CONSOLE = Logger.new(STDOUT)
  CONSOLE.formatter = proc { |severity, datetime, progname, msg|
    "#{msg}\n"
  }
  CONSOLE.datetime_format = "%Y-%m-%d %H:%M:%S"
  OUTFILE = FileLogIO.new("logs/default.log")
  FILELOG = Logger.new(OUTFILE)
  FILELOG.datetime_format = "%Y-%m-%d %H:%M:%S"

  LOG = Object.new
  def LOG.debug(str)
    CONSOLE.debug(str)
  end
  def LOG.info(str)
    CONSOLE.info(str)
    FILELOG.info(str)
  end
  def LOG.warn(str)
    CONSOLE.warn(str)
    FILELOG.warn(str)
  end
  def LOG.error(str)
    CONSOLE.error(str)
    FILELOG.error(str)
  end
  def LOG.fatal(str)
    CONSOLE.fatal(str)
    FILELOG.fatal(str)
  end
  
  def get_page_location(page_url, options={})
    where = options.key?("where") ? options["where"] : "web_cache"
    
    uri = URI.parse(page_url)
    return nil unless uri and (uri.scheme == "http" or uri.scheme == "https")
    
    uri_query = nil
    unless uri.query.nil?
      uri_query = sort_query(uri.query)
    end
    uri_host = uri.host
    uri_path = uri.path
    uri_folder = (uri_path[-1] == '/') ? uri_path[0..-2] : File.dirname(uri_path)
    uri_file = uri_path.sub(uri_folder + "/", "")
    uri_file = "index" if (uri_file.nil? or uri_file.empty?)
    uri_file += "~QMARK~#{uri_query}" unless uri_query.nil?
    
    save_path = File.join(where, uri_host, uri_folder, uri_file)
    save_path
  end

  def get_page_data(page_url, options={})
    replace = options.key?(:replace) ? options[:replace] : false
    save_path = get_page_location(page_url, options)
    save_folder = File.dirname(save_path)
    FileUtils::mkdir_p save_folder
    
    if File.file?(save_path) and not replace
      data = ""
      open(save_path, 'r') do |file|
        data = file.read
      end
      return data
    end
    open(page_url) do |webpage|
      data = webpage.read
      open(save_path, 'w') do |file|
        file.write data
      end
    end
    return data
  end
  
  BLOCK_LEVELS = [:address, :article, :aside, :blockquote, :canvas, :dd, :div, :dl, :fieldset, :figcaption, :figure, :footer, :form, :h1, :h2, :h3, :h4, :h5, :h6, :header, :hgroup, :hr, :li, :main, :nav, :noscript, :ol, :output, :p, :pre, :section, :table, :tfoot, :ul, :video, :br]
  def get_text_on_line(node, options={})
    stop_at = []
    stop_at = options[:stop_at] if options and options.key?(:stop_at)
    stop_at = [stop_at] if not stop_at.is_a?(Array)
    
    forward = true
    forward = options[:forward] if options and options.key?(:forward)
    
    backward = true
    backward = options[:backward] if options and options.key?(:backward)
    
    include_node = true
    include_node = options[:include_node] if options and options.key?(:include_node)
    
    text = ""
    text = node.text if include_node
    previous_element = node.previous
    while backward and previous_element and not BLOCK_LEVELS.include?(previous_element.name) and not BLOCK_LEVELS.include?(previous_element.name.to_sym) and not stop_at.include?(previous_element.name) and not stop_at.include?(previous_element.name.to_sym)
      text = previous_element.text + text
      previous_element = previous_element.previous
    end
    next_element = node.next
    while forward and next_element and not BLOCK_LEVELS.include?(next_element.name) and not BLOCK_LEVELS.include?(next_element.name.to_sym) and not stop_at.include?(next_element.name) and not stop_at.include?(next_element.name.to_sym)
      text = text + next_element.text
      next_element = next_element.next
    end
    text
  end
  
  def standardize_chapter_url(url)
    uri = URI.parse(url)
    if uri.host["dreamwidth.org"]
      uri.fragment = nil
      set_url_params(clear_url_params(uri.to_s), {style: :site})
    else
      url
    end
  end
  
  def sort_query(query)
    return nil if query.nil?
    return nil if query.empty?
    
    query_hash = CGI::parse(query)
    sorted_keys = query_hash.keys.sort
    
    sorted_list = []
    sorted_keys.each do |key|
      sorted_list << [key, query_hash[key]]
    end
    sorted_query = URI.encode_www_form(sorted_list)
    
    return nil if sorted_query.empty?
    sorted_query
  end

  def set_url_params(chapter_url, params={})
    uri = URI(chapter_url)
    uri_query = (uri.query or "")
    paramstr = URI.encode_www_form(params)
    uri_query += "&" unless uri_query.empty? or paramstr.empty?
    uri_query += paramstr
    
    uri_query = sort_query(uri_query)
    uri.query = uri_query
    uri.to_s
  end
  
  def clear_url_params(chapter_url)
    uri = URI(chapter_url)
    uri.query = ""
    uri.to_s
  end
  
  def get_url_params_for(chapter_url, param_name)
    return nil if chapter_url.nil? or chapter_url.empty?
    uri = URI(chapter_url)
    return [] unless uri.query and not uri.query.empty?
    query_hash = CGI::parse(uri.query)
    return [] unless query_hash.key?(param_name)
    return query_hash[param_name]
  end
  
  def get_url_param(chapter_url, param_name, default=nil)
    return default if chapter_url.nil? or chapter_url.empty?
    params = get_url_params_for(chapter_url, param_name)
    return default if params.empty?
    return params.first
  end

  def get_chapters_data(group, where="")
    where = "web_cache/chapterDetails_#{group}.txt" if where == ""
    
    chapterRep = GlowficEpub::Chapters.new
    
    return chapterRep unless File.file?(where)
    File.open(where, "rb") do |f|
      chapterRep.from_json! f.read
    end
    return chapterRep
  end

  def set_chapters_data(chapters, group, others={})
    where = others.key?("where") ? others["where"] : ""
    old = others.key?("old") ? others["old"] : false
    where = unless where == ""
      where
    else
      if old
        "web_cache/oldChapterDetails_#{group}.txt"
      else
        "web_cache/chapterDetails_#{group}.txt"
      end
    end
    if chapters.is_a?(Array)
      chapterRep = GlowficEpub::Chapters.new
      chapters.each do |chapter|
        chapterRep.chapters << chapter
      end
      chapters = chapterRep
    end
    temp = chapters.to_json
    File.open(where, "wb") do |f|
      f.write(temp)
      #f.write(temp)
    end
  end

  def get_prev_chapter_pages(group)
    chapters = get_chapters_data(group)
    prev_lengths = {}
    chapters.each do |chapter|
      prev_lengths[chapter.url] = chapter.pageCount unless chapter.pageCount == 0
    end
    prev_lengths
  end

  def get_prev_chapter_loads(group)
    chapters = get_chapters_data(group)
    prev_loads = {}
    chapters.each do |chapter|
      prev_loads[chapter.url] = chapter.fullyLoaded unless chapter.pageCount == 0
    end
    prev_loads
  end
end
