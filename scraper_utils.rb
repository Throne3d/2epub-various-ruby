module ScraperUtils
  require 'fileutils'
  require 'open-uri'
  require 'open_uri_redirections'

  class FileLogIO
    attr_reader :file
    def initialize(defaultFile=nil)
      return unless defaultFile
      FileUtils::mkdir_p(File.dirname(defaultFile))
      @file = File.open(defaultFile, 'a+')
    end

    def file=(filename)
      @file.close if @file
      FileUtils::mkdir_p(File.dirname(filename))
      @file = File.open(filename, 'a+')
      @file.sync = true
    end

    def set_output_params(process, group=nil)
      self.file = 'logs/' + Time.now.strftime('%Y-%m-%d %H %M ') + " #{process}" + (group.nil? ? '' : "_#{group}") + '.log'
    end

    def write(data); @file.try(:write, data); end
    def close; @file.try(:close); end
  end

  DEBUGGING = false

  CONSOLE = Logger.new(STDOUT)
  CONSOLE.formatter = proc { |_severity, _datetime, _progname, msg|
    "#{msg}\n"
  }
  CONSOLE.datetime_format = "%Y-%m-%d %H:%M:%S"

  OUTFILE = FileLogIO.new("logs/default.log")
  FILELOG = Logger.new(OUTFILE)
  FILELOG.datetime_format = "%Y-%m-%d %H:%M:%S"

  LOG = Object.new
  def LOG.debug(str)
    return unless DEBUGGING
    CONSOLE.debug(str) unless DEBUGGING == :file
    FILELOG.debug(str) if DEBUGGING == :file
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
  def LOG.progress(message=nil, progress=-1, count=-1)
    # e.g. "Saving chapters", 0, 300
    if progress < 0
      # end the progress!
      CONSOLE << "\n"
      LOG.info(message)
      return
    end

    perc = progress / count.to_f * 100
    CONSOLE << CONSOLE.formatter.call(Logger::Severity::INFO, Time.now, CONSOLE.progname, "\r#{message}… [#{progress}/#{count}] #{perc.round}%").chomp if CONSOLE.info?
  end

  COLLECTION_LIST_URL = 'https://raw.githubusercontent.com/Throne3d/databox/master/collection_pages.txt'
  MOIETY_LIST_URL = 'https://raw.githubusercontent.com/Throne3d/databox/master/moiety_list.json'
  REPORT_LIST_URL = 'https://raw.githubusercontent.com/Throne3d/databox/master/toc_report.json'

  FIC_NAME_MAPPING = {
    # put the mappings so subsets of followings come first (efful before effulgence, zod before zodiac, etc.)
    effulgence: [:efful, :effulgence],
    incandescence: [:incan, :incandescence],
    pixiethreads: [:pix, :pixie, :pixiethreads],
    radon: [:radon, :absinthe],
    opalescence: [:opal, :opalescence],
    zodiac: [:zodiac],
    silmaril: [:silm, :silmaril],
    lighthouse: [:light, :lighthouse],
    rapid_nova: [:rapid, :nova, :rapidnova, :rapid_nova],

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
    reptest: [:reptest],
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
    opalescence: "https://glowfic.com/boards/12",
    zodiac: "https://glowfic.com/boards/7",
    silmaril: "https://alicornutopia.dreamwidth.org/31812.html",
    lighthouse: "https://glowfic.com/boards/16",
    rapid_nova: "https://glowfic.com/boards/30",

    #Sandboxes
    glowfic: "http://glowfic.dreamwidth.org/2015/06/",
    constellation: "https://glowfic.com/boards/",

    mwf_leaf: "http://manyworlds.boards.net/thread/80/backstage-leafy-glowfic-index",
    mwf_lioncourt: "http://manyworlds.boards.net/thread/104/party-thread-index",

    #Authors
    sandbox: "http://alicornutopia.dreamwidth.org/1640.html?style=site",
    marri: "http://marrinikari.dreamwidth.org/1634.html?style=site",
    peterverse: "http://peterverse.dreamwidth.org/1643.html?style=site",
    maggie: "http://maggie-of-the-owls.dreamwidth.org/454.html?style=site",
    throne: "https://theotrics.dreamwidth.org/268.html?style=site",
    lintamande: "https://glowfic.com/users/34/",

    #Test
    test: "https://glowfic.com/boards/7",
    reptest: "https://glowfic.com/boards/7",
    temp_starlight: "https://alicornutopia.dreamwidth.org/29069.html",
    report: "https://glowfic.com/boards/"
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
    rapid_nova: "Jarnvidr & Pedro",

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
    radon: "Radon Absinthe",
    rapid_nova: "Rapid Nova",

    glowfic: "Glowfic Community",

    mwf_leaf: "Leafy Glowfic",
    mwf_lioncourt: "Lioncourt Party",

    sandbox: "Alicorn's Sandboxes",
    marri: "Marri's Sandboxes",
    maggie: "Maggie's Sandboxes",
    throne: "Throne3d's Sandboxes",
    lintamande: "Lintamande's Sandboxes",

    test: "Test EPUB",
    temp_starlight: "Starlight"
  }
  FIC_NAMESTRINGS.default_proc = proc {|hash, key| hash[key] = key.titleize }

  def is_huge_cannot_dirty(group)
    group = group.group if group.is_a?(Chapters)
    group == :sandbox || group == :constellation
  end

  def date_display(date, strf="%Y-%m-%d %H:%M")
    date.try(:strftime, strf)
  end

  def get_page_location(page_url, options={})
    standardize_params(options)
    where = options.fetch(:where, 'web_cache')

    uri = URI.parse(page_url)
    return unless uri && (uri.scheme == 'http' || uri.scheme == 'https')

    uri_query = sort_query(uri.query)
    uri_host = uri.host
    uri_path = uri.path
    if uri_path.end_with?('/')
      uri_folder = uri_path[0..-2]
      uri_file = 'index'
    else
      uri_folder = File.dirname(uri_path)
      uri_file = File.basename(uri_path)
    end
    uri_file += "~QMARK~#{uri_query}" unless uri_query.nil?

    File.join(where, uri_host, uri_folder, uri_file)
  end
  def sanitize_local_path(local_path)
    local_path.gsub("\\", "~BACKSLASH~").gsub(":", "~COLON~").gsub("*", "~ASTERISK~").gsub("?", "~QMARK~").gsub("\"", "~QUOT~").gsub("<", "~LT~").gsub(">", "~GT~").gsub("|", "~BAR~")
  end

  def download_file(file_url, options={})
    LOG.debug "download_file('#{file_url}', #{options})"
    standardize_params(options)
    headers = options.fetch(:headers, {})
    save_path = options[:save_path] || get_page_location(file_url, options)

    save_folder = File.dirname(save_path)
    FileUtils::mkdir_p save_folder

    retries = 3
    success = has_retried = false
    begin
      param_hash = {:ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE, :allow_redirections => :all}.merge(headers)
      open(file_url, param_hash) do |webpage|
        open(save_path, 'w') do |file|
          file.write webpage.read
        end
      end
      sleep 0.05
      success = true
    rescue OpenURI::HTTPError, SocketError, Net::OpenTimeout, Net::ReadTimeout => error
      LOG.error "Error loading file (#{file_url}); #{retries} retr#{retries==1 ? 'y' : 'ies'} left"
      LOG.debug error

      retries -= 1
      has_retried = true
      retry if retries >= 0
    end

    unless success
      LOG.error "Failed to load page (#{file_url})"
      return
    end

    LOG.debug "Downloaded page"
    LOG.info "Successfully loaded file (#{file_url})." if has_retried
    save_path
  end

  def get_page(file_url, options={})
    LOG.debug "get_page('#{file_url}', #{options})"

    standardize_params(options)
    replace = options[:replace]
    save_path = options[:save_path] || get_page_location(file_url, options)

    return save_path if File.file?(save_path) && !replace
    download_file(file_url, options)
  end

  def get_page_data(page_url, options={})
    LOG.debug "get_page_data('#{page_url}', #{options})"
    standardize_params(options)
    file_path = get_page(page_url, options)

    return unless File.file?(file_path)

    open(file_path, 'r') { |file| file.read }
  end

  BLOCK_LEVELS = [:address, :article, :aside, :blockquote, :canvas, :dd, :div, :dl, :fieldset, :figcaption, :figure, :footer, :form, :h1, :h2, :h3, :h4, :h5, :h6, :header, :hgroup, :hr, :li, :main, :nav, :noscript, :ol, :output, :p, :pre, :section, :table, :tfoot, :ul, :video, :br]
  def get_text_on_line(node, options={})
    standardize_params(options)
    raise(ArgumentError, "Invalid parameter combo: :after and :forward") if options.key?(:after) && options.key?(:forward)
    raise(ArgumentError, "Invalid parameter combo: :before and :backward") if options.key?(:before) && options.key?(:backward)

    stop_at = options.fetch(:stop_at, [])
    stop_at = [stop_at] unless stop_at.is_a?(Array)

    forward = options.fetch(:forward, options.fetch(:after, true))
    backward = options.fetch(:backward, options.fetch(:before, true))

    include_node = options.fetch(:include_node, true)

    text = node.text if include_node
    text ||= ''

    previous_element = node.previous
    while backward && previous_element && !BLOCK_LEVELS.include?(previous_element.name.to_sym) && !stop_at.include?(previous_element.name) && !stop_at.include?(previous_element.name.to_sym)
      text = previous_element.text + text
      previous_element = previous_element.previous
    end

    next_element = node.next
    while forward && next_element && !BLOCK_LEVELS.include?(next_element.name.to_sym) && !stop_at.include?(next_element.name) && !stop_at.include?(next_element.name.to_sym)
      text = text + next_element.text
      next_element = next_element.next
    end

    text
  end

  def standardize_chapter_url(url)
    url = url.sub('glowfic.herokuapp.com', 'glowfic.com')
    uri = URI.parse(url)
    uri.fragment = nil
    if uri.host.end_with?('dreamwidth.org')
      thread = get_url_param(url, "thread")
      params = {style: :site}
      params[:thread] = thread unless thread.blank?
      return set_url_params(clear_url_params(uri.to_s), params)
    elsif uri.host.end_with?('vast-journey-9935.herokuapp.com') || uri.host.end_with?('glowfic.com')
      return clear_url_params(uri.to_s)
    else
      url
    end
  end

  def standardize_params(params={})
    params.keys.each do |key|
      params[key.to_sym] = params.delete(key) if key.is_a?(String)
    end
    params
  end

  def sort_query(query)
    return if query.blank?

    query_hash = CGI::parse(query)
    sorted_keys = query_hash.keys.sort

    sorted_list = []
    sorted_keys.each do |key|
      sorted_list << [key, query_hash[key]]
    end
    sorted_query = URI.encode_www_form(sorted_list)

    return if sorted_query.empty?
    sorted_query
  end

  def set_url_params(chapter_url, params={})
    uri = URI(chapter_url)
    uri_query = uri.query || ''
    paramstr = URI.encode_www_form(params)
    uri_query += '&' unless uri_query.empty? || paramstr.empty?
    uri_query += paramstr

    uri.query = sort_query(uri_query)
    uri.to_s
  end

  def clear_url_params(chapter_url)
    uri = URI(chapter_url)
    uri.query = ''
    uri.to_s
  end

  def get_url_params_for(chapter_url, param_name)
    return if chapter_url.blank?
    uri = URI(chapter_url)
    return [] unless uri.query.present?
    query_hash = CGI::parse(uri.query)
    return [] unless query_hash.key?(param_name)
    query_hash[param_name]
  end
  def get_url_param(chapter_url, param_name, default=nil)
    return default if chapter_url.blank?
    params = get_url_params_for(chapter_url, param_name)
    params.first || default
  end

  def oldify_chapters_data(group, options={})
    old_where = options.fetch(:where, "web_cache/chapterdetails_#{group}.txt")
    new_where = options.fetch(:new, '')

    old_where = old_where.tr("\\", "/")
    new_where = new_where.tr("\\", "/")
    return unless File.file?(old_where)

    if new_where.empty?
      where_bits = old_where.split('/')
      where_bits[-1] = "old_" + where_bits.last
      new_where = where_bits * '/'
    end

    File.open(old_where, "r") do |oldf|
      File.open(new_where, "w") do |newf|
        newf.write oldf.read
      end
    end
  end

  def get_chapters_data(group, options={})
    where = options.fetch(:where, "web_cache/chapterdetails_#{group}.txt")
    trash_messages = options.fetch(:trash_messages, false)

    chapterRep = GlowficEpub::Chapters.new(group: group, trash_messages: trash_messages)

    return chapterRep unless File.file?(where)
    File.open(where, "r") do |f|
      chapterRep.from_json! f.read.scrub
    end
    chapterRep
  end

  def set_chapters_data(chapters, group, others={})
    standardize_params(others)
    where = others.fetch(:where, "web_cache/chapterdetails_#{group}.txt")

    if chapters.is_a?(Array)
      chapterRep = GlowficEpub::Chapters.new
      chapters.each do |chapter|
        chapterRep.chapters << chapter
      end
      chapters = chapterRep
    end
    temp = chapters.to_json
    File.open(where, 'w') do |f|
      f.write(temp)
    end
    LOG.debug "Saved data for group: #{group}" + (others.empty? ? '' : " (#{others.inspect})")
  end

  def clear_old_data(group=nil)
    @temp_data = {} if group.nil?
    @temp_data.delete(group)
  end

  def get_old_data(group)
    @temp_data ||= {}
    @temp_data[group] ||= get_chapters_data(group)
  end

  def get_prev_chapter_detail(group, others={})
    if group.is_a?(Hash) && others.nil?
      others = group
      group = others[:group]
    end
    if others.present?
      detail = others[:detail]
      only_present = others[:only_present]
      chapters = others[:chapters] || others[:chapter_list]
    end
    group ||= chapters.group
    chapters ||= get_old_data(group)

    prev_detail = {}
    chapters.each do |chapter|
      prev_detail[chapter.url] = chapter.try(detail)
    end
    prev_detail.select! {|_key, value| value.present?} if only_present
    prev_detail
  end
  def get_prev_chapter_pages(group)
    get_prev_chapter_detail(group, detail: :pages)
  end
  def get_prev_chapter_check_pages(group)
    get_prev_chapter_detail(group, detail: :check_pages, only_present: true)
  end

  def shortenURL(longURL)
    return '' if longURL.blank?
    uri = URI.parse(longURL)
    if uri.query.present?
      query = CGI.parse(uri.query)
      query.delete("style")
      query.delete("view")
      query.delete("per_page")
      query = URI.encode_www_form(query)
      uri.query = query
    end
    uri.host = uri.host.sub(/\.dreamwidth\.org$/, '.dreamwidth').sub('vast-journey-9935.herokuapp.com', 'constellation').sub('www.glowfic.com', 'constellation').sub('glowfic.com', 'constellation')
    uri.to_s.sub(/^https?\:\/\//, '').sub(/\.html($|(?=\?))/, '')
  end

  def csscol_to_rgb(csscol)
    csscol = csscol.strip.upcase
    csscol = csscol[1..-1] if csscol.start_with?('#')
    if csscol.length == 3
      css_r = csscol[0]
      css_g = csscol[1]
      css_b = csscol[2]
    elsif csscol.length == 6
      css_r = csscol[0..1]
      css_g = csscol[2..3]
      css_b = csscol[4..5]
    else
      raise(ArgumentError, "csscol is not a CSS hex color")
    end
    r = @hex.index(css_r[0]) * 16 + @hex.index(css_r[-1])
    g = @hex.index(css_g[0]) * 16 + @hex.index(css_g[-1])
    b = @hex.index(css_b[0]) * 16 + @hex.index(css_b[-1])
    [r,g,b]
  end
  def rgb_to_hsl(r, g=nil, b=nil)
    # accepts r,g,b or [r,g,b], returns [h,s,l]
    if r.is_a?(Array)
      g = r[1]
      b = r[2]
      r = r[0]
    end

    r = r / 255.0
    g = g / 255.0
    b = b / 255.0
    max = [r,g,b].max
    min = [r,g,b].min
    l = (max + min) / 2.0

    if (max == min)
      h = s = 1.0 # hack so gray gets sent to the end
      return [h,s,l]
    end

    d = max - min
    s = (l > 0.5) ? d / (2.0 - max - min) : d / (max + min)
    case (max)
    when r
      h = (g - b) / d + (g < b ? 6.0 : 0.0)
    when g
      h = (b - r) / d + 2.0
    when b
      h = (r - g) / d + 4.0
    end
    h = h / 6.0

    [h,s,l]
  end
  def hsl_comp(hsl1, hsl2)
    if hsl1[0] == hsl2[0]
      # if hues are same, use luminosity
      hsl1[2] <=> hsl2[2]
    else
      # if hue is different, use that
      hsl1[0] <=> hsl2[0]
    end
  end
end
