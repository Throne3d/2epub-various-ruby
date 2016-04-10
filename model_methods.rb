module GlowficEpubMethods
  class FileLogIO
    def initialize(defaultFile=nil)
      @file = File.open(defaultFile, 'a+') unless defaultFile.nil?
    end
    
    def file=(filename)
      @file.close if @file
      @file = File.open(filename, 'a+')
      @file.sync = true
    end
    
    def file
      @file
    end
    
    def set_output_params(process, group=nil)
      self.file = "logs/" + Time.now.strftime("%Y-%m-%d %H %M ") + "#{process}" + (group.nil? ? "" : "_#{group}") + ".log"
    end
    
    def write(data)
      @file.write(data) if @file
    end
    
    def close
      @file.close if @file
    end
  end
  
  DEBUGGING = false
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
    CONSOLE.debug(str) if DEBUGGING
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
    standardize_params(options)
    where = options.key?(:where) ? options[:where] : "web_cache"
    
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
  
  def download_file(file_url, options={})
    standardize_params(options)
    replace = options.key?(:replace) ? options[:replace] : false
    if options.key?(:retry)
      options[:do_retry] = options[:retry]
      options.delete(:retry)
    end
    
    save_path = options[:save_path] if options.key?(:save_path)
    
    retries = 3
    if options.key?(:do_retry)
      if options[:do_retry].is_a?(Integer)
        retries = options[:do_retry]
      elsif options[:do_retry].nil? or options[:do_retry].is_a?(TrueClass) or options[:do_retry].is_a?(FalseClass)
        retries = 0 unless options[:do_retry]
      end
    elsif options.key?(:retries)
      retries = options[:retries]
    end
    
    options.delete(:do_retry) if options.key?(:do_retry)
    options[:retries] = retries
    
    raise(ArgumentError, "Retries must be an integer. #{options}") unless retries.is_a?(Integer)
    
    LOG.debug "download_file('#{file_url}', #{options})"
    save_path = get_page_location(file_url, options) unless save_path
    save_folder = File.dirname(save_path)
    FileUtils::mkdir_p save_folder
    
    if File.file?(save_path) and not replace
      LOG.debug "File exists already, not replacing"
      return save_path
    end
    
    success = false
    begin
      open(file_url) do |webpage|
        open(save_path, 'w') do |file|
          file.write webpage.read
        end
      end
      success = true
    rescue OpenURI::HTTPError => error
      LOG.error "Error loading file (#{file_url}); #{retries == 0 ? 'No' : retries} retr#{retries==1 ? 'y' : 'ies'} left"
      LOG.debug error
      
      retries -= 1
      retry if retries >= 0
    end
    LOG.debug "Downloaded page" if success
    LOG.error "Failed to load page (#{file_url})" unless success
    
    save_path
  end

  def get_page_data(page_url, options={})
    standardize_params(options)
    LOG.debug "get_page_data('#{page_url}', #{options})"
    file_path = download_file(page_url, options)
    
    if !File.file?(file_path)
      return nil
    end
    
    data = ""
    open(file_path, 'r') do |file|
      data = file.read
    end
    data
  end
  
  BLOCK_LEVELS = [:address, :article, :aside, :blockquote, :canvas, :dd, :div, :dl, :fieldset, :figcaption, :figure, :footer, :form, :h1, :h2, :h3, :h4, :h5, :h6, :header, :hgroup, :hr, :li, :main, :nav, :noscript, :ol, :output, :p, :pre, :section, :table, :tfoot, :ul, :video, :br]
  def get_text_on_line(node, options={})
    standardize_params(options)
    raise(ArgumentError, "Invalid parameter combo: :after and :forward") if options.key?(:after) and options.key?(:forward)
    raise(ArgumentError, "Invalid parameter combo: :before and :backward") if options.key?(:before) and options.key?(:backward)
    options = {} unless options
    
    stop_at = []
    stop_at = options[:stop_at] if options.key?(:stop_at)
    stop_at = [stop_at] if not stop_at.is_a?(Array)
    
    forward = true
    forward = options[:forward] if options.key?(:forward)
    forward = options[:after] if options.key?(:after)
    
    backward = true
    backward = options[:backward] if options.key?(:backward)
    backward = options[:before] if options.key?(:before)
    
    include_node = true
    include_node = options[:include_node] if options.key?(:include_node)
    
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
    if uri.host.end_with?("dreamwidth.org")
      uri.fragment = nil
      set_url_params(clear_url_params(uri.to_s), {style: :site})
    else
      url
    end
  end
  
  def standardize_params(params={})
    params.keys.each do |key|
      if key.is_a? String
        params[key.to_sym] = params[key]
        params.delete(key)
      end
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
  
  def oldify_chapters_data(group, options={})
    old_where = options.key?(:where) ? options[:where] : (options.key?(:old) ? options[:old] : (options.key?(:old_where) ? options[:old_where] : "web_cache/chapterdetails_#{group}.txt"))
    new_where = options.key?(:new) ? options[:new] : (options.key?(:new_where) ? options[:new_where] : "")
    
    old_where = old_where.gsub("\\", "/")
    new_where = new_where.gsub("\\", "/")
    if new_where == ""
      where_bits = old_where.split("/")
      where_bits[-1] = "old_" + where_bits.last
      new_where = where_bits * "/"
    end
    
    return if not File.file?(old_where)
    File.open(old_where, "rb") do |old|
      File.open(new_where, "wb") do |new|
        new.write old.read
      end
    end
  end
  
  def get_chapters_data(group, options={})
    where = (options.key?(:where)) ? options[:where] : "web_cache/chapterdetails_#{group}.txt"
    trash_messages = (options.key?(:trash_messages)) ? options[:trash_messages] : false
    
    chapterRep = GlowficEpub::Chapters.new(group: group, trash_messages: trash_messages)
    
    return chapterRep unless File.file?(where)
    File.open(where, "rb") do |f|
      chapterRep.from_json! f.read
    end
    return chapterRep
  end

  def set_chapters_data(chapters, group, others={})
    standardize_params(others)
    where = others.key?(:where) ? others[:where] : ""
    old = others.key?(:old) ? others[:old] : false
    where = unless where == ""
      where
    else
      if old
        "web_cache/old_chapterdetails_#{group}.txt"
      else
        "web_cache/chapterdetails_#{group}.txt"
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
    end
  end

  def get_prev_chapter_pages(group)
    chapters = get_chapters_data(group)
    prev_pages = {}
    chapters.each do |chapter|
      prev_pages[chapter.url] = chapter.pages if chapter.pages and not chapter.pages.empty?
    end
    prev_pages
  end
end
