module GlowficSiteHandlers
  require 'model_methods'
  require 'models'
  require 'uri'
  require 'date'
  include GlowficEpubMethods
  include GlowficEpub::PostType
  
  def self.get_handler_for(chapter)
    site_handlers = GlowficSiteHandlers.constants.map {|c| GlowficSiteHandlers.const_get(c) }
    site_handlers.select! {|c| c.is_a? Class and c < GlowficSiteHandlers::SiteHandler }
    chapter_handlers = site_handlers.select {|c| c.handles? chapter}
    return chapter_handlers.first if chapter_handlers.length == 1
    chapter_handlers
  end
  
  class SiteHandler
    include GlowficEpub
    def self.handles?(chapter)
      false
    end
    def get_updated(chapter)
      nil
    end
    def handles?(chapter)
      return self.class.handles?(chapter)
    end
    def initialize(options = {})
      @group = nil
      @group = options[:group] if options.key?(:group)
      @group_folder = "web_cache"
      @group_folder += "/#{@group}" if @group
      @chapter_list = []
      @chapter_list = options[:chapters] if options.key?(:chapters)
      @chapter_list = options[:chapter_list] if options.key?(:chapter_list)
      @chapter_list = GlowficEpub::Chapters.new if @chapter_list.is_a?(Array) and @chapter_list.empty?
    end
  end
  
  class DreamwidthHandler < SiteHandler
    attr_reader :download_count
    def self.handles?(chapter)
      return false if chapter.nil?
      chapter_url = (chapter.is_a?(GlowficEpub::Chapter)) ? chapter.url : chapter
      return false if chapter_url.nil? or chapter_url.empty?
      
      uri = URI.parse(chapter_url)
      return uri.host.end_with?("dreamwidth.org")
    end
    def initialize(options = {})
      super options
      @face_cache = {} # {"alicornutopia" => {"pen" => "(url)"}}
      @face_id_cache = {} # {"alicornutopia#pen" => "(url)"}
      # When retrieved in get_face_by_id
      @moiety_cache = {}
    end
    
    def get_full(chapter, options = {})
      if chapter.is_a?(GlowficEpub::Chapter)
        params = {style: :site}
        params[:thread] = chapter.thread if chapter.thread
        chapter_url = set_url_params(clear_url_params(chapter.url), params)
      else
        chapter_url = chapter
      end
      return nil unless self.handles?(chapter_url)
      notify = options.key?(:notify) ? options[:notify] : true
      is_new = options.key?(:new) ? options[:new] : false
      
      page_urls = [chapter_url]
      comment_ids = []
      
      current_page_data = get_page_data(chapter_url, replace: true, where: @group_folder)
      @download_count+=1
      LOG.debug "Got a page in get_full"
      current_page = Nokogiri::HTML(current_page_data)
      LOG.debug "Nokogiri processed a page in get_full"
      
      full_comments = current_page.css('.comment-wrapper.full')
      LOG.debug "found fulls"
      full_comments.each do |full_comment|
        comment_id = full_comment.parent.try(:[], :id)
        next unless comment_id
        comment_ids << comment_id
      end
      
      partial_comments = current_page.css('.comment-wrapper.partial')
      LOG.debug "found partials"
      partial_comments.each do |partial_comment|
        comment_id = partial_comment.parent.try(:[], :id)
        next unless comment_id
        next if comment_ids.include?(comment_id)
        
        comment_link = partial_comment.at_css('h4.comment-title a')
        LOG.debug "found link"
        (LOG.warning "Issue finding link while processing chapter `#{chapter}`, comment #{partial_comment}" and return nil) if comment_link.nil? or not comment_link.try(:[], :href)
        
        new_url = comment_link.try(:[], :href)
        new_thread = get_url_param(new_url, "thread")
        params = {style: :site}
        params[:thread] = new_thread if new_thread
        (LOG.warning "No chapter thread?" and return nil) unless new_thread
        LOG.debug "Got thread"
        new_page_url = set_url_params(clear_url_params(new_url), params)
        LOG.debug "Niced URL to: #{new_page_url}"
        
        @comment_ids = []
        sub_page_urls = get_full(new_page_url, options)
        next if sub_page_urls.nil?
        
        page_urls += sub_page_urls
        comment_ids += @comment_ids
      end
      
      @comment_ids = comment_ids
      return page_urls
    end
    
    def get_updated(chapter, options = {})
      return nil unless self.handles?(chapter)
      notify = options.key?(:notify) ? options[:notify] : true
      
      is_new = true
      prev_pages = chapter.pages
      if prev_pages and not prev_pages.empty?
        is_new = false
        first_page_url = prev_pages.first
        
        first_page_old_data = get_page_data(first_page_url, replace: false, where: @group_folder)
        first_page_new_data = get_page_data(first_page_url, replace: true, where: 'temp')
        
        first_page_old = Nokogiri::HTML(first_page_old_data)
        first_page_new = Nokogiri::HTML(first_page_new_data)
        
        old_content = first_page_old.at_css('#content')
        new_content = first_page_new.at_css('#content')
        
        old_html = old_content.inner_html
        new_html = new_content.inner_html
        
        changed = (old_html != new_html)
        
        pages_exist = true
        prev_pages.each_with_index do |page_url, i|
          page_loc = get_page_location(page_url)
          if not File.file?(page_loc)
            pages_exist = false
            LOG.debug "Failed to find a file (page #{i}) for chapter #{chapter}"
            break
          end
        end #Check if all the pages exist, in case someone deleted them
        
        LOG.debug "Content is different for #{chapter}" if changed
        if pages_exist and not changed
          LOG.info "#{chapter.title}: #{chapter.pages.length} page#{chapter.pages.length != 1 ? 's' : ''}" if notify
          return chapter
        end
      end
      
      #Hasn't been done before, or it's outdated, or some pages were deleted; re-get.
      @download_count = 0
      pages = get_full(chapter, options.merge({new: (not changed)}))
      chapter.pages = pages
      LOG.info "#{is_new ? 'New:' : 'Updated:'} #{chapter.title}: #{chapter.pages.length} page#{chapter.pages.length != 1 ? 's' : ''} (Got #{@download_count} page#{@download_count != 1 ? 's' : ''})" if notify
      return chapter
    end
    
    def get_moiety_by_profile(profile)
      return @moiety_cache[profile] if @moiety_cache.key?(profile)
      user_id = profile.gsub('_', '-')
      return @moiety_cache[user_id] if @moiety_cache.key?(user_id)
      
      moieties = []
      MOIETIES.keys.each do |author|
        moieties << author if MOIETIES[author].include?(profile) or MOIETIES[author].include?(user_id)
      end
      
      icon_moiety = moieties * ' '
      (LOG.error "No moiety for #{profile}") if icon_moiety.empty?
      @moiety_cache[user_id] = icon_moiety
      icon_moiety
    end
    
    def get_face_by_id(face_id, default=nil)
      return @face_id_cache[face_id] if @face_id_cache.key?(face_id)
      user_profile = face_id.split('#').first
      face_name = face_id.sub("#{user_profile}#", "")
      face_name = "default" if face_name == face_id
      face_name = "default" if face_name == "(Default)"
      @icon_page_errors = [] unless @icon_page_errors
      @icon_errors = [] unless @icon_errors
      
      return default if @icon_page_errors.include?(user_profile)
      
      unless @face_cache.key?(user_profile) or @face_cache.key?(user_profile.gsub('_', '-'))
        user_id = user_profile.gsub('_', '-')
        
        icon_moiety = get_moiety_by_profile(user_profile)
        
        icon_page_data = get_page_data("http://#{user_id}.dreamwidth.org/icons", replace: true)
        icon_page = Nokogiri::HTML(icon_page_data)
        icons = icon_page.at_css('#content').css('.icon-row .icon')
        default_icon = icon_page.at_css('#content').at_css('.icon.icon-default')
        
        if icons.nil? or icons.empty?
          LOG.error "No icons for #{user_id}."
          @icon_page_errors << user_profile
          return
        end
        (LOG.error "No default icon for #{user_id}.") if default_icon.nil?
        
        icon_hash = {}
        icons.each do |icon_element|
          icon_img = icon_element.at_css('.icon-image img')
          icon_src = icon_img.try(:[], :src)
          
          (LOG.error "Failed to find an img URL on the icon page for #{user_id}" and next) if icon_src.nil? or icon_src.empty?
          
          icon_keywords = icon_element.css('.icon-info .icon-keywords li')
          
          params = {}
          params[:moiety] = icon_moiety
          params[:imageURL] = icon_src
          params[:user] = user_id
          params[:user_display] = user_profile
          
          icon_keywords.each do |keyword_element|
            params[:keyword] = keyword_element.text.strip
            params[:unique_id] = "#{user_id}##{params[:keyword]}"
            face = Face.new(params)
            icon_hash[params[:keyword]] = face
            
            @chapter_list.add_face(face)
          end
          if (icon_element == default_icon)
            params[:keyword] = "default"
            params[:unique_id] = "#{user_id}#default"
            face = Face.new(params)
            icon_hash[:default] = face
            
            @chapter_list.add_face(face)
          end
        end
        
        @face_cache[user_profile] = icon_hash
      end
      
      icons_hash = @face_cache.key?(user_profile) ? @face_cache[user_profile] : @face_cache[user_profile.gsub('_', '-')]
      @face_id_cache[face_id] = icons_hash[face_name] if icons_hash.key?(face_name)
      @face_id_cache[face_id] = icons_hash[:default] if (face_name.downcase == "default" or face_name == :default) and icons_hash.key?(:default)
      return @face_id_cache[face_id] if @face_id_cache.key?(face_id)
      
      LOG.error "Failed to find a face for user: #{user_profile} and face: #{face_name}" unless @icon_errors.include?(face_id)
      @icon_errors << face_id unless @icon_errors.include?(face_id)
      return default
    end
    
    def make_message(message_element, options = {})
      in_context = (options.key?(:in_context) ? options[:in_context] : true)
      
      message_id = message_element["id"].sub("comment-", "").sub("entry-", "")
      message_type = (message_element["id"]["entry"]) ? PostType::ENTRY : PostType::REPLY
      
      userpic = message_element.at_css(".userpic img")
      author_name = message_element.at_css('span.ljuser').try(:[], "lj:user")
      
      face_url = ""
      face_name = "default"
      if userpic and userpic["title"]
        if userpic["title"] != author_name
          face_name = userpic["title"].sub("#{author_name}: ", "").split(" (").first
        end
        if userpic["src"]
          face_url = userpic["src"]
        end
      end
      
      params = {}
      edit_element = message_element.at_css(".contents .edittime")
      if edit_element
        edit_text = edit_element.at_css(".datetime").text.strip
        params[:edittime] = DateTime.strptime(edit_text, "%Y-%m-%d %H:%M (%Z)")
        edit_element.remove
      end
      params[:content] = message_element.at_css('.entry-content, .comment-content').inner_html
      params[:face] = get_face_by_id("#{author_name}##{face_name}")
      params[:author] = author_name
      params[:id] = message_id
      params[:chapter] = @chapter
      
      if params[:face].nil? and not face_url.empty?
        face_params = {}
        face_params[:moiety] = get_moiety_by_profile(author_name)
        face_params[:imageURL] = face_url
        face_params[:user] = author_name.gsub('_', '-')
        face_params[:user_display] = author_name
        face_params[:keyword] = face_name
        face_params[:unique_id] = "#{face_params[:user]}##{face_name}"
        face = Face.new(face_params)
        params[:face] = face
      end
      
      if message_type == PostType::ENTRY
        params[:entry_title] = message_element.at_css('.entry-title').text.strip
        
        time_text = message_element.at_css('.header .datetime').text.strip
        time_text = time_text[1..-1].strip if time_text.start_with?("@")
        params[:time] = DateTime.strptime(time_text, "%Y-%m-%d %I:%M %P")
        
        entry = Entry.new(params)
      else
        parent_link = message_element.at_css(".link.commentparent a")
        if parent_link
          parent_href = parent_link[:href]
          parent_id = "cmt" + get_url_param(parent_href, "thread")
          @replies.each do |reply|
            params[:parent] = reply if reply.id == parent_id
          end
        else
          params[:parent] = @chapter.entry
        end
        
        time_text = message_element.at_css('.header .datetime').text.strip
        params[:time] = DateTime.strptime(time_text, "%Y-%m-%d %I:%M %P (%Z)")
        
        reply = Reply.new(params)
      end
    end
  
    def get_replies(chapter, options = {})
      return nil unless self.handles?(chapter)
      notify = options.key?(:notify) ? options[:notify] : true
      
      pages = chapter.pages
      (LOG.error "Chapter (#{chapter.title}) has no pages" and return) if pages.nil? or pages.empty?
      
      @chapter = chapter
      @replies = []
      pages.each do |page_url|
        page_data = get_page_data(page_url, replace: false, where: @group_folder)
        page = Nokogiri::HTML(page_data)
        
        page_content = page.at_css('#content')
        nsfw_warning = page_content.at_css('.panel.callout')
        if nsfw_warning
          nsfw_warning_text = nsfw_warning.at_css('text-center')
          if nsfw_warning_text and nsfw_warning_text.text["Discretion Advised"]
            (LOG.error('Page had discretion advised warning!') and break)
          end
        end
        
        if @replies.empty?
          entry_element = page_content.at_css('.entry')
          entry = make_message(entry_element)
          chapter.entry = entry
        end
        
        comments = page_content.css('.comment-wrapper.full')
        comments.each do |comment|
          comment_element = comment.at_css('.comment')
          reply = make_message(comment_element)
          @replies << reply
        end
      end
      
      LOG.info "#{chapter.title}: #{pages.length} page#{pages.length == 1 ? '' : 's'}" if notify
      
      chapter.replies=@replies
    end
  end
  
  class ConstellationHandler < SiteHandler
    attr_reader :download_count
    def self.handles?(chapter)
      return false if chapter.nil?
      chapter_url = (chapter.is_a?(GlowficEpub::Chapter)) ? chapter.url : chapter
      return false if chapter_url.nil? or chapter_url.empty?
      
      uri = URI.parse(chapter_url)
      return uri.host.end_with?("vast-journey-9935.herokuapp.com")
    end
    def initialize(options = {})
      super options
      @face_id_cache = {} # {"6951" => "[is a face: ahein, imgur..., etc.]"}
      @char_page_cache = {}
      # When retrieved in get_face_by_id
      @moiety_cache = {}
    end
    
    def get_full(chapter, options = {})
      if chapter.is_a?(GlowficEpub::Chapter)
        params = {per_page: 'all'}
        chapter_url = set_url_params(clear_url_params(chapter.url), params)
      else
        chapter_url = chapter
      end
      return nil unless self.handles?(chapter_url)
      notify = options.key?(:notify) ? options[:notify] : true
      is_new = options.key?(:new) ? options[:new] : false
      
      page_urls = [chapter_url]
      
      current_page_data = get_page_data(chapter_url, replace: true, where: @group_folder)
      @download_count+=1
      LOG.debug "Got a page in get_full"
      current_page = Nokogiri::HTML(current_page_data)
      LOG.debug "Nokogiri processed a page in get_full"
      
      return page_urls
    end
    
    def get_updated(chapter, options = {})
      return nil unless self.handles?(chapter)
      notify = options.key?(:notify) ? options[:notify] : true
      
      is_new = true
      prev_pages = chapter.pages
      if prev_pages and not prev_pages.empty?
        is_new = false
        
        first_page_url = prev_pages.first
        
        first_page_old_data = get_page_data(first_page_url, replace: false, where: @group_folder)
        first_page_new_data = get_page_data(first_page_url, replace: true, where: 'temp')
        
        first_page_old = Nokogiri::HTML(first_page_old_data)
        first_page_new = Nokogiri::HTML(first_page_new_data)
        
        old_content = first_page_old.at_css('#content')
        new_content = first_page_new.at_css('#content')
        
        old_html = old_content.inner_html
        new_html = new_content.inner_html
        
        changed = (old_html != new_html)
        
        pages_exist = true
        prev_pages.each_with_index do |page_url, i|
          page_loc = get_page_location(page_url)
          if not File.file?(page_loc)
            pages_exist = false
            LOG.debug "Failed to find a file (page #{i}) for chapter #{chapter}"
            break
          end
        end #Check if all the pages exist, in case someone deleted them
        
        LOG.debug "Content is different for #{chapter}" if changed
        if pages_exist and not changed
          LOG.info "#{chapter.title}: #{chapter.pages.length} page#{chapter.pages.length != 1 ? 's' : ''}" if notify
          return chapter
        end
      end
      
      #Hasn't been done before, or it's outdated, or some pages were deleted; re-get.
      @download_count = 0
      pages = get_full(chapter, options.merge({new: (not changed)}))
      chapter.pages = pages
      LOG.info "#{is_new ? 'New:' : 'Updated:'} #{chapter.title}: #{chapter.pages.length} page#{chapter.pages.length != 1 ? 's' : ''} (Got #{@download_count} page#{@download_count != 1 ? 's' : ''})" if notify
      return chapter
    end
    
    def get_moiety_by_id(character_id)
      char_page_data = get_page_data("https://vast-journey-9935.herokuapp.com/characters/#{character_id}", replace: false)
      char_page = Nokogiri::HTML(char_page_data)
      
      breadcrumb1 = char_page.at_css('.flash.subber a')
      if breadcrumb1.text.strip == "Characters"
        user_info = char_page.at_css('#header #user-info')
        user_info.at_css('img').try(:remove)
        return user_info.text.strip
      end
      username = breadcrumb1.text.split("Characters").first.strip
      username = username[0..-3] if username.end_with?("'s")
      username
    end
    
    def get_face_by_id(face_id, default=nil)
      return @face_id_cache[face_id] if @face_id_cache.key?(face_id)
      
      icon_id = face_id.split('#').last
      return @face_id_cache[icon_id] if @face_id_cache.key?(icon_id)
      character_id = face_id.sub("##{icon_id}", '')
      
      character_id = nil if character_id == face_id
      character_id = nil if character_id.nil? or character_id.empty?
      
      @icon_page_errors = [] unless @icon_page_errors
      @icon_errors = [] unless @icon_errors
      
      return default if @icon_page_errors.include?(character_id)
      
      if character_id and not @char_page_cache.key?(character_id)
        char_page_data = get_page_data("https://vast-journey-9935.herokuapp.com/characters/#{character_id}", replace: true)
        char_page = Nokogiri::HTML(char_page_data)
        icons = char_page.css(".gallery-icon")
        default_icon_url = char_page.at_css("#content img").try(:[], :src)
        
        icon_moiety = get_moiety_by_id(character_id)
        
        char_screen_ele = char_page.at_css("#content > b")
        if char_screen_ele
          char_screen = char_screen_ele.text.strip
          char_screen_ele.remove
        else
          char_screen = ""
        end
        
        char_page.at_css("#content img").try(:remove)
        
        char_name = char_page.at_css("#content").text.strip.split("\n").first.strip
        
        char_display = char_name
        char_display += " (#{char_screen})" unless char_screen.nil? or char_screen.empty?
        
        if icons.nil? or icons.empty?
          LOG.error "No icons for character ##{character_id}."
          @icon_page_errors << character_id
          return
        end
        
        icon_hash = {}
        icons.each do |icon_element|
          icon_link = icon_element.at_css('a')
          icon_img = icon_link.at_css('img')
          icon_src = icon_img.try(:[], :src)
          
          (LOG.error "Failed to find an img URL on the icon page for character ##{character_id}" and next) if icon_src.nil? or icon_src.empty?
          
          icon_keyword = icon_img.try(:[], :title)
          icon_numid = icon_src.split("icons/").last
          
          params = {}
          params[:moiety] = icon_moiety
          params[:imageURL] = icon_src
          params[:user] = character_id
          params[:user_display] = char_display
          
          params[:keyword] = icon_keyword
          params[:unique_id] = icon_numid
          face = Face.new(params)
          icon_hash[icon_numid] = face
          
          @chapter_list.add_face(face)
          @face_id_cache[params[:unique_id]] = face
          
          if (icon_src == default_icon_url and not icon_hash.key?(:default))
            params[:keyword] = "default"
            params[:unique_id] = "#{character_id}#default"
            face = Face.new(params)
            icon_hash[:default] = face
            
            @chapter_list.add_face(face)
          end
        end
        
        @char_page_cache[character_id] = icon_hash
      end
      
      return @face_id_cache[icon_id] if @face_id_cache.key?(icon_id)
      
      if not character_id
        icon_page_data = get_page_data("https://vast-journey-9935.herokuapp.com/icons/#{icon_id}", replace: true)
        icon_page = Nokogiri::HTML(icon_page_data)
        
        params = {}
        params[:moiety] = ""
        params[:imageURL] = icon_page.at_css('#content img').try(:[], :src)
        params[:user] = ""
        params[:user_display] = ""
        
        icon_page.at_css('#content img').try(:remove)
        params[:keyword] = icon_page.at_css('#content').text.sub("Keyword:", "").strip.split("\n").first.strip
        params[:unique_id] = icon_id
        face = Face.new(params)
        @chapter_list.add_face(face)
        @face_id_cache[params[:unique_id]] = face
      end
      
      return @face_id_cache[face_id] if @face_id_cache.key?(face_id)
      return @face_id_cache[icon_id] if @face_id_cache.key?(icon_id)
      
      LOG.error "Failed to find a face for character: #{character_id} and face: #{icon_id}" unless @icon_errors.include?(face_id)
      @icon_errors << face_id unless @icon_errors.include?(face_id)
      return default
    end
    
    def make_message(message_element, options = {})
      permalink_btn = message_element.at_css(".post-edit-box img[alt='Link']")
      if permalink_btn
        permalink_btn = permalink_btn.parent
        message_id = permalink_btn["href"].split('posts/').last.split('replies/').last.split("#").first
        message_type = (permalink_btn["href"]["post"]) ? PostType::ENTRY : PostType::REPLY
      end
      
      userpic = message_element.at_css(".post-icon img")
      author_element = message_element.at_css(".post-author a")
      author_name = author_element.text.strip
      author_id = author_element["href"].split("users/").last
      
      character_element = message_element.at_css('.post-character a')
      character_id = nil
      character_name = nil
      if character_element
        character_id = character_element["href"].split("characters/").last
        character_name = character_element.text.strip
      end
      
      face_url = ""
      face_name = "default"
      face_id = ""
      if userpic
        face_id = userpic.parent["href"].split("icons/").last
        face_url = userpic["src"]
        face_name = userpic["title"]
      end
      
      date_element = message_element.at_css('.post-footer')
      date_element.at_css('a').try(:remove)
      date_str = date_element.text.strip
      if date_str.end_with?("|")
        date_str = date_str[0..-2].strip
      end
      
      params = {}
      create_date = date_str.split("|").first.sub("Posted", "").strip
      params[:time] = DateTime.strptime(create_date, "%b %d, %Y %l:%M %p")
      if date_str["|"]
        edit_date = date_str.split("|").last.sub("Updated", "").strip
        params[:edittime] = DateTime.strptime(edit_date, "%b %d, %Y %l:%M %p")
      end
      
      message_content = message_element.at_css('.padding-10')
      message_content.at_css('.post-info-box').try(:remove)
      message_content.at_css('.post-edit-box').try(:remove)
      message_content.at_css('.post-footer').try(:remove)
      params[:content] = message_content.text
      face_id = [character_id, face_id].reject{|thing| thing.nil?} * '#'
      params[:face] = get_face_by_id(face_id)
      params[:author] = character_id
      params[:id] = message_id
      params[:chapter] = @chapter
      
      if params[:face].nil? and not face_url.empty?
        face_params = {}
        face_params[:moiety] = author_name
        face_params[:imageURL] = face_url
        face_params[:user] = character_id
        face_params[:user_display] = character_name or author_name
        face_params[:keyword] = face_name
        face_params[:unique_id] = face_id
        face = Face.new(face_params)
        params[:face] = face
      end
      
      if message_type == PostType::ENTRY
        params[:entry_title] = @entry_title
        
        entry = Entry.new(params)
        @previous_message = entry
      else
        params[:parent] = @previous_message if @previous_message
        
        reply = Reply.new(params)
        @previous_message = reply
      end
    end
  
    def get_replies(chapter, options = {})
      return nil unless self.handles?(chapter)
      notify = options.key?(:notify) ? options[:notify] : true
      
      pages = chapter.pages
      (LOG.error "Chapter (#{chapter.title}) has no pages" and return) if pages.nil? or pages.empty?
      
      @entry_title = nil
      @chapter = chapter
      @replies = []
      pages.each do |page_url|
        page_data = get_page_data(page_url, replace: false, where: @group_folder)
        page = Nokogiri::HTML(page_data)
        
        @entry_title = page.at_css("#post-title").text.strip unless @entry_title
        page_content = page.at_css('#content')
        
        @chapter.title_extras = page.at_css('.post-subheader').try(:text).try(:strip)
        
        if @replies.empty?
          paginator = page_content.at_css('.paginator')
          
          @entry_element = paginator.previous_element
          entry = make_message(@entry_element)
          chapter.entry = entry
        end
        
        comments = page_content.css('.post-container')
        comments.each do |comment_element|
          next if comment_element == @entry_element
          
          reply = make_message(comment_element)
          @replies << reply
        end
      end
      
      LOG.info "#{chapter.title}: #{pages.length} page#{pages.length == 1 ? '' : 's'}" if notify
      
      chapter.replies=@replies
    end
  end
end
