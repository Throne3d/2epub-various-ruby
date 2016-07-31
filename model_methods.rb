module GlowficEpubMethods
  require 'fileutils'
  require 'open-uri'
  require 'open_uri_redirections'
  class FileLogIO
    def initialize(defaultFile=nil)
      FileUtils::mkdir_p(File.dirname(defaultFile)) if defaultFile
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
  
  COLLECTION_LIST_URL = 'https://gist.githubusercontent.com/Nineza/776e8136c058cf9957df65ccaf27f552/raw/collection_pages.txt'
  MOIETY_LIST_URL = 'https://gist.githubusercontent.com/Nineza/8b8b47312b6b8b92f16fd4c91aa67cd4/raw/moiety_list.json'
  REPORT_LIST_URL = 'https://gist.githubusercontent.com/Nineza/5149441eebc2d83dbef27547e74a0f1e/raw/toc_report.json'
  
  FIC_NAME_MAPPING = {
    # put the mappings so subsets of followings come first (efful before effulgence, zod before zodiac, etc.)
    effulgence: [:efful, :effulgence],
    incandescence: [:incan, :incandescence],
    pixiethreads: [:pix, :pixiethreads],
    radon: [:radon, :absinthe],
    opalescence: [:opal, :opalescence],
    zodiac: [:zodiac],
    silmaril: [:silm, :silmaril],
    lighthouse: [:light, :lighthouse],
    
    glowfic: [:othersandbox, :sandbox2, :glowfic],
    constellation: [:const, :constellation, :glowfic2, :sandbox3],
    
    mwf_leaf: [:mwf, :mwf_1, :leaf, :mwf_leaf],
    mwf_lioncourt: [:mwf_2, :lion, :mwf_lion, :lioncourt, :mwf_lioncourt],
    
    sandbox: [:sandbox, :alicorn],
    marri: [:marri, :marrinikari],
    peterverse: [:pedro, :peterverse],
    maggie: [:maggie, :maggieoftheowls, :"maggie-of-the-owls"],
    throne: [:throne, :throne3d, :theotrics],
    lintamande: [:lintamande, :elves],
    
    test: [:test],
    temp_starlight: [:temp_starlight, :starlight],
    report: [:report, :daily]
  }
  FIC_SHOW_AUTHORS = [:glowfic, :constellation, :sandbox, :marri, :peterverse, :maggie, :throne, :lintamande, :test, :report, :mwf_leaf, :mwf_lioncourt]
  FIC_TOCS = {
    #Continuities
    effulgence: "http://edgeofyourseat.dreamwidth.org/2121.html?style=site",
    incandescence: "http://alicornutopia.dreamwidth.org/7441.html?style=site",
    pixiethreads: "http://pixiethreads.dreamwidth.org/613.html?style=site",
    radon: "http://radon-absinthe.dreamwidth.org/295.html?style=site",
    opalescence: "https://vast-journey-9935.herokuapp.com/boards/12",
    zodiac: "https://vast-journey-9935.herokuapp.com/boards/7",
    silmaril: "https://alicornutopia.dreamwidth.org/31812.html",
    lighthouse: "https://vast-journey-9935.herokuapp.com/boards/16",
    
    #Sandboxes
    glowfic: "http://glowfic.dreamwidth.org/2015/06/",
    constellation: "https://vast-journey-9935.herokuapp.com/boards/",
    
    mwf_leaf: "http://manyworlds.boards.net/thread/80/backstage-leafy-glowfic-index",
    mwf_lioncourt: "http://manyworlds.boards.net/thread/104/party-thread-index",
    
    #Authors
    sandbox: "http://alicornutopia.dreamwidth.org/1640.html?style=site",
    marri: "http://marrinikari.dreamwidth.org/1634.html?style=site",
    peterverse: "http://peterverse.dreamwidth.org/1643.html?style=site",
    maggie: "http://maggie-of-the-owls.dreamwidth.org/454.html?style=site",
    throne: "https://theotrics.dreamwidth.org/268.html?style=site",
    lintamande: "https://vast-journey-9935.herokuapp.com/users/34/",
    
    #Test
    test: "https://vast-journey-9935.herokuapp.com/boards/7",
    temp_starlight: "https://alicornutopia.dreamwidth.org/29069.html",
    report: "https://vast-journey-9935.herokuapp.com/boards/"
  }
  FIC_AUTHORSTRINGS = {
    effulgence: "Alicorn & Kappa",
    incandescence: "Alicorn & Aestrix",
    pixiethreads: "Aestrix & Kappa",
    radon: "Kappa & AndaisQ",
    opalescence: "Moriwen & Throne",
    zodiac: "Pedro & Throne",
    silmaril: "Alicorn & Lintamande",
    lighthouse: "CuriousDiscoverer & Pedro",
    
    glowfic: "Misc",
    constellation: "Misc",
    
    mwf_leaf: "Kappa & Misc",
    mwf_lioncourt: "MWF",
    
    sandbox: "Alicorn & Misc",
    marri: "Marri & Misc",
    peterverse: "Pedro & Misc",
    maggie: "Maggie & Misc",
    throne: "Throne3d & Misc",
    lintamande: "Lintamande & Misc",
    
    test: "Pedro & Throne3d",
    temp_starlight: "Alicorn & Pedro"
  }
  FIC_AUTHORSTRINGS.default = "Unknown"
  FIC_NAMESTRINGS = {
    effulgence: "Effulgence",
    incandescence: "Incandescence",
    pixiethreads: "Pixiethreads",
    radon: "Radon Absinthe",
    opalescence: "Opalescence",
    zodiac: "Zodiac",
    silmaril: "Silmaril",
    lighthouse: "Lighthouse",
    
    glowfic: "Glowfic Community",
    constellation: "Constellation",
    
    mwf_leaf: "Leafy Glowfic",
    mwf_lioncourt: "Lioncourt Party",
    
    sandbox: "Alicorn's Sandboxes",
    marri: "Marri's Sandboxes",
    peterverse: "Peterverse",
    maggie: "Maggie's Sandboxes",
    throne: "Throne3d's Sandboxes",
    lintamande: "Lintamande's Sandboxes",
    
    test: "Test EPUB",
    temp_starlight: "Starlight"
  }
  FIC_NAMESTRINGS.default_proc = proc {|hash, key| hash[key] = key.titleize }
  
  def date_display(date, strf="%Y-%m-%d %H:%M")
    date.try(:strftime, strf)
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
  
  def sanitize_local_path(local_path)
    local_path.gsub("\\", "~BACKSLASH~").gsub(":", "~COLON~").gsub("*", "~ASTERISK~").gsub("?", "~QMARK~").gsub("\"", "~QUOT~").gsub("<", "~LT~").gsub(">", "~GT~").gsub("|", "~BAR~")
  end
  
  def download_file(file_url, options={})
    standardize_params(options)
    replace = options.key?(:replace) ? options[:replace] : false
    if options.key?(:retry)
      options[:do_retry] = options[:retry]
      options.delete(:retry)
    end
    
    save_path = options[:save_path] if options.key?(:save_path)
    headers = options[:headers] if options.key?(:headers)
    
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
    has_retried = false
    begin
      param_hash = {:ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE, :allow_redirections => :all}
      param_hash.merge!(headers) if headers
      open(file_url, param_hash) do |webpage|
        open(save_path, 'w') do |file|
          file.write webpage.read
        end
      end
      sleep 0.05
      success = true
    rescue OpenURI::HTTPError, SocketError, Net::OpenTimeout => error
      LOG.error "Error loading file (#{file_url}); #{retries == 0 ? 'No' : retries} retr#{retries==1 ? 'y' : 'ies'} left"
      LOG.debug error
      
      retries -= 1
      has_retried = true
      retry if retries >= 0
    end
    LOG.debug "Downloaded page" if success
    LOG.info "Successfully loaded file (#{file_url})." if has_retried and success
    LOG.error "Failed to load page (#{file_url})" unless success
    
    return save_path if success
    return nil unless success
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
      thread = get_url_param(url, "thread")
      params = {style: :site}
      params[:thread] = thread unless thread.nil? or thread.empty?
      set_url_params(clear_url_params(uri.to_s), params)
    elsif uri.host.end_with?("vast-journey-9935.herokuapp.com")
      uri.fragment = nil
      params = {per_page: :all}
      set_url_params(clear_url_params(uri.to_s), params)
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
    LOG.debug "Saved data for group: #{group}" + (others.empty? ? "" : " (#{others.inspect})")
  end
  
  
  def get_old_data(group)
    @temp_data ||= {}
    @temp_data[group] = get_chapters_data(group) unless @temp_data.key?(group)
    @temp_data[group]
  end
  def get_prev_chapter_detail(group, others={})
    if others.is_a?(Hash)
      detail = others[:detail]
      remove_empty = others[:remove_empty] or others[:reject_empty]
      only_present = others[:only_present]
    else
      detail = others
    end
    remove_empty ||= false
    
    chapters = get_old_data(group)
    
    prev_detail = {}
    chapters.each do |chapter|
      prev_detail[chapter.url] = chapter.try(detail)
    end
    prev_detail.reject! {|key, value| value.nil? or value.empty?} if remove_empty
    prev_detail.select! {|key, value| value.present?} if only_present
    prev_detail
  end
  def get_prev_chapter_details(group, others={})
    get_prev_chapter_detail(group, others)
  end
  
  def get_prev_chapter_pages(group)
    get_prev_chapter_detail(group, :pages)
  end
  
  def get_prev_chapter_check_pages(group)
    get_prev_chapter_detail(group, detail: :check_pages, only_present: true)
  end
end
