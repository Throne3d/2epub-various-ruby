module GlowficSiteHandlers
  require 'model_methods'
  require 'models'
  require 'mechanize'
  include GlowficEpubMethods
  include GlowficEpub::PostType
  
  def self.get_handler_for(thing)
    site_handlers = GlowficSiteHandlers.constants.map {|c| GlowficSiteHandlers.const_get(c) }
    site_handlers.select! {|c| c.is_a? Class and c < GlowficSiteHandlers::SiteHandler }
    chapter_handlers = site_handlers.select {|c| c.handles? thing}
    return chapter_handlers.first if chapter_handlers.length == 1
    chapter_handlers
  end
  
  class SiteHandler
    include GlowficEpub
    attr_reader :group, :chapter_list
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
      @download_count = 0
      @downcache = {}
      @giricache = {}
    end
    def message_attributes(options = {})
      @message_attributes unless options.present?
      only_attrs = options.key?(:attributes) ? options[:attributes] : (options.key?(:only) ? options[:only] : (options.key?(:only_attrs) ? options[:only_attrs] : nil))
      except_attrs = options.key?(:except) ? options[:except] : (options.key?(:except_attrs) ? options[:except_attrs] : nil)
      raise("Not allowed both :only and :expect on get_replies; #{only_attrs * ','} and #{except_attrs * ','}") if only_attrs and except_attrs
      message_attributes = (only_attrs ? only_attrs : msg_attrs)
      message_attributes.reject! {|thing| except_attrs.include?(thing)} if except_attrs
      message_attributes.uniq!
      @message_attributes = message_attributes
    end
    def already_processed(chapter, options = {})
      if chapter.processed and chapter.processed.is_a?(Array) and chapter.processed.contains_all? message_attributes(options)
        if chapter.replies.empty?
          LOG.error "#{chapter.title}: cached data contains no replies; not using"
          return false
        else
          msg_str = "#{chapter.title}: unchanged, cached data used"
          if block_given?
            yield msg_str
          elsif notify
            LOG.info msg_str
          end
          return true
        end
      end
      false
    end
    def down_or_cache(page, options = {})
      where = options.key?(:where) ? options[:where] : nil
      @downcache[where] = [] unless @downcache.key?(where)
      
      downd = @downcache[where].include?(page)
      options[:replace] = !downd
      data = get_page_data(page, options)
      @download_count+=1 unless downd
      @downcache[where] << page unless downd
      data
    end
    def giri_or_cache(page, options = {})
      LOG.debug "giri_or_cache(\"#{page}\"" + (options.empty? ? "" : ", #{options}") + ")"
      where = options.key?(:where) ? options[:where] : nil
      replace = options.key?(:replace) ? options[:replace] : true
      @giricache[where] = {} unless @giricache.key?(where)
      
      return @giricache[where][page] if @giricache[where].key?(page)
      
      predone = has_cache?(page, options)
      data = (replace ? down_or_cache(page, options) : get_page_data(page, options))
      giri = Nokogiri::HTML(data)
      @giricache[where][page] = giri if predone
      giri
    end
    def remove_cache(page, options = {})
      where = options.key?(:where) ? options[:where] : nil
      return unless @downcache.key?(where)
      @downcache[where].delete(page)
    end
    def remove_giri_cache(page, options = {})
      where = options.key?(:where) ? options[:where] : nil
      return unless @giricache.key?(where)
      old_cache = nil
      if @giricache[where].key?(page)
        old_cache = @giricache[where][page]
        @giricache[where].delete(page)
      end
      old_cache
    end
    def nokogiri_or_cache(page, options={})
      giri_or_cache(page, options)
    end
    def has_cache?(page, options={})
      where = (options.key?(:where)) ? options[:where] : nil
      @downcache[where] = [] unless @downcache.key?(where)
      @downcache[where].include?(page)
    end
    def save_down(page, data, options={})
      where = (options.key?(:where)) ? options[:where] : nil
      @downcache[where] = [] unless @downcache.key?(where)
      
      @downcache[where] << page unless @downcache[where].include?(page)
      loc = get_page_location(page, options)
      open(loc, 'w') do |f|
        f.write data
      end
      data
    end
    def msg_attrs
      @msg_attrs ||= [:time, :edittime, :author, :face]
    end
  end
  
  class DreamwidthHandler < SiteHandler
    attr_reader :download_count
    def self.handles?(thing)
      return false if thing.nil?
      if thing.is_a?(GlowficEpub::Author)
        return thing.unique_id.start_with?('dreamwidth#')
      else
        chapter_url = (thing.is_a?(GlowficEpub::Chapter)) ? thing.url : thing
        return false if chapter_url.nil? or chapter_url.empty?
        
        uri = URI.parse(chapter_url)
        return uri.host.end_with?("dreamwidth.org")
      end
    end
    def initialize(options = {})
      super options
      @face_cache = {} # {"alicornutopia" => {"pen" => "(url)"}}
      @face_id_cache = {} # {"alicornutopia#pen" => "(url)"}
      # When retrieved in get_face_by_id
      @face_url_cache = {}
      @face_param_cache = {}
      @face_issue_cache = []
      @author_id_cache = {}
      @author_param_cache = {}
      
      @page_list = []
      @repeated_page_cache = {}
      
      @moiety_cache = {}
      
      @downloaded = []
      
      @mech_agent = Mechanize.new
    end
    
    def get_comment_link(comment)
      @partial = comment.at_css('> .dwexpcomment > .partial')
      @full = comment.at_css('> .dwexpcomment > .full') unless @partial
      if @partial
        comm_link = @partial.at_css('.comment-title').try(:at_css, 'a').try(:[], :href)
      else
        comm_link = @full.try(:at_css, '.commentpermalink').try(:at_css, 'a').try(:[], :href)
      end
      LOG.error "partial and no comm_link" if @partial and not comm_link
      LOG.error "no partial, no full" if not @partial and not @full
      LOG.error "#{(not @full) ? 'not ' : ''}full and no comm_link" if not @partial and not comm_link
      if block_given?
        yield @partial, @full, comm_link
      end
      if comm_link
        params = {style: :site}
        params[:thread] = get_url_param(comm_link, "thread")
        comm_link = set_url_params(clear_url_params(comm_link), params)
      end
      return comm_link
    end
    def get_permalink_for(message)
      if message.post_type == "PostType::ENTRY"
        set_url_params(clear_url_params(message.chapter.url), {view: :flat})
      else
        if message.page_no
          set_url_params(clear_url_params(message.chapter.url), {view: :flat, page: message.page_no}) + "#comment-#{message.id}"
        else
          set_url_params(clear_url_params(message.chapter.url), {thread: message.id}) + "#comment-#{message.id}"
        end
      end
    end
    def get_undiscretioned(url, options = {})
      current_page = options.key?(:current_page) ? options[:current_page] : (options.key?(:current) ? options[:current] : nil)
      options.delete(:current_page)
      options.delete(:current)
      
      if current_page.is_a?(String)
        current_page = Nokogiri::HTML(current_page)
      end
      where = options.key?(:where) ? options[:where] : nil
      unless current_page.present?
        current_page = giri_or_cache(url, options)
      end
      
      content = current_page.at_css('#content')
      
      text_thing = 'Discretion Advised'
      
      nsfw_warning = content.at_css('.panel.callout').try(:at_css, '.text-center').try(:text)
      if nsfw_warning.try(:[], text_thing)
        LOG.debug "Got a discretion advised – trying to fix with Mechanize"
        page = @mech_agent.get(url)
        sleep 0.05
        discretion_form = page.forms.select{|form| form.action["/adult_concepts"]}.first
        
        remove_giri_cache(url, options)
        if discretion_form
          data_page = discretion_form.submit
          save_down(url, data_page.content, options)
        else
          save_down(url, page.content, options)
        end
        current_page = giri_or_cache(url, options)
        nsfw_warning = current_page.at_css('.panel.callout').try(:at_css, '.text-center').try(:text)
        if nsfw_warning.try(:[], text_thing)
          LOG.error "Failed to fix discretion advised warning for page #{url}"
          return nil
        else
          LOG.debug "Fixed a discretion advised warning"
        end
      end
      
      return current_page
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
      
      page_urls = []
      
      params = {style: :site, view: :flat, page: 1}
      first_page = set_url_params(clear_url_params(chapter.url), params)
      first_page_stuff = get_undiscretioned(first_page, where: @group_folder)
      
      unless first_page_stuff
        @error = "Page failed to load (discretion advised warning?)"
        @success = false
        return
      end
      
      first_page_content = first_page_stuff.at_css('#content')
      
      page_count = first_page_content.try(:at_css, '.comment-pages').try(:at_css, '.page-links').try(:at_css, 'a:last').try(:text).try(:strip)
      page_count = page_count.gsub("[","").gsub("]","").to_i if page_count
      page_count = 1 unless page_count
      
      1.upto(page_count).each do |num|
        params[:page] = num
        this_page = set_url_params(clear_url_params(chapter.url), params)
        down_or_cache(this_page, where: @group_folder)
        page_urls << this_page
      end
      
      chapter.processed = false if chapter.is_a?(GlowficEpub::Chapter)
      
      @success = true
      return page_urls
    end
    def get_updated(chapter, options = {})
      return nil unless self.handles?(chapter)
      notify = options.key?(:notify) ? options[:notify] : true
      
      is_new = true
      prev_pages = chapter.pages
      check_pages = chapter.check_pages
      if prev_pages and not prev_pages.empty?
        is_new = false
        
        @download_count = 0
        changed = false
        same_comment_count = false
        check_pages.reverse.each_with_index do |check_page, i|
          if i == check_pages.count - 1 && same_comment_count
            LOG.debug "Same non-main pages & comment count, skipping main page."
            next
          end
          page_location = get_page_location(check_page, where: @group_folder)
          was_file = File.file?(page_location)
          
          page_old_data = get_page_data(check_page, replace: false, where: @group_folder)
          unless was_file
            LOG.debug "check page #{i}, #{check_page}, didn't exist in the group folder"
            changed = true
            break
          end
          page_new = get_undiscretioned(check_page, where: 'temp')
          page_old = Nokogiri::HTML(page_old_data)
          page_cache = (i == check_pages.count - 1) ? nil : chapter.check_page_data[check_page]
          page_cache = Nokogiri::HTML(page_cache) if page_cache
          
          chapter.check_page_data_set(check_page, page_old_data) unless page_cache || i == check_pages.count - 1
          
          unless page_new
            @error = "Page failed to load (discretion advised warning?)"
            @success = false
            return
          end
          
          old_content = page_old.at_css('#content')
          new_content = page_new.at_css('#content')
          cache_content = page_cache.at_css('#content') if page_cache
          
          old_comment_count = old_content.at_css('.entry-readlink').try(:text).try(:strip).try(:[], /\d+/)
          new_comment_count = new_content.at_css('.entry-readlink').try(:text).try(:strip).try(:[], /\d+/)
          cache_comment_count = cache_content.at_css('.entry-readlink').try(:text).try(:strip).try(:[], /\d+/) if page_cache
          same_comment_count = true if old_comment_count == new_comment_count && old_comment_count.present? && new_comment_count.present? && (page_cache.blank? || cache_comment_count == old_comment_count)
          
          old_content.at_css(".entry-interaction-links").try(:remove)
          new_content.at_css(".entry-interaction-links").try(:remove)
          cache_content.at_css(".entry-interaction-links").try(:remove) if page_cache
          
          changed = (old_content.inner_html != new_content.inner_html)
          if changed
            LOG.debug "check page #{i}, #{check_page}, was different"
            break
          end
          if page_cache && !changed
            changed2 = (old_content.inner_html != cache_content.inner_html)
            if changed2
              LOG.info "check page cache in JSON (#{i}, #{check_page}) was different. other cache wasn't. fixing."
              changed = changed2
              break
            end
          end
          LOG.debug "check page #{i} was not different"
        end
        
        LOG.debug "#{(not changed) ? 'not ' : ''}changed!"
        
        pages_exist = true
        prev_pages.each_with_index do |page_url, i|
          page_loc = get_page_location(page_url, where: @group_folder)
          if not File.file?(page_loc)
            pages_exist = false
            LOG.error "Failed to find a file (page #{i}) for chapter #{chapter}. Will get again."
            break
          end
        end #Check if all the pages exist, in case someone deleted them
        
        LOG.debug "Content is different for #{chapter}" if changed
        if pages_exist and not changed
          msg_str = "#{chapter.title}: #{chapter.pages.length} page#{chapter.pages.length != 1 ? 's' : ''} (checked #{@download_count} page#{@download_count != 1 ? 's' : ''})"
          if block_given?
            yield msg_str
          elsif notify
            LOG.info msg_str
          end
          return chapter
        end
      end
      
      chapter.processed = false
      
      #Hasn't been done before, or it's outdated, or some pages were deleted; re-get.
      @download_count = 0
      @success = false
      pages = get_full(chapter, options.merge({new: (not changed)}))
      
      params = {style: :site}
      params[:thread] = chapter.thread if chapter.thread
      main_page = set_url_params(clear_url_params(chapter.url), params)
      
      main_page_stuff = get_undiscretioned(main_page, where: @group_folder)
      unless main_page_stuff
        @error = "Page failed to load (discretion advised warning?)"
        @success = false
      end
      
      comment_count = 0
      if main_page_stuff
        #Check the comments and find each branch-end and get a link to them all :D
        chapter.check_pages = [main_page]
        main_page_content = main_page_stuff.at_css('#content')
        comments = main_page_content.css('.comment-thread')
        prev_chain = []
        prev_depth = 0
        comm_depth = 0
        comments.each do |comment|
          comment_count += 1
          prev_chain = prev_chain.drop(prev_chain.length - 3) if prev_chain.length > 3
          
          comm_depth = 0
          (LOG.error "Error: failed comment depth" and next) unless comment[:class]["comment-depth-"]
          comm_depth = comment[:class].split('comment-depth-').last.split(/\s+/).first.to_i
          
          if comm_depth > prev_depth
            prev_chain << comment
            prev_depth = comm_depth
            next
          end
          
          LOG.debug "depth (#{comm_depth}) was lower than prev_depth (#{prev_depth}), therefore new branch, let's track the previous one."
          
          upper_comment = prev_chain.first
          @cont = false
          comm_link = get_comment_link(upper_comment) do |partial, full, comm_link|
            unless comm_link
              LOG.error "Error: failed upper comment link (for depth #{comm_depth})"
              @cont = true
            end
          end
          next if @cont
          
          chapter.check_pages << comm_link
          LOG.debug "Added to chapter check_pages: #{comm_link}"
          
          prev_chain = [comment]
          prev_depth = comm_depth
        end
        
        unless prev_chain.empty?
          upper_comment = prev_chain.first
          comm_link = get_comment_link(upper_comment) do |partial, full, comm_link|
            unless comm_link
              LOG.error "Error: failed upper comment link (for depth #{comm_depth})"
            end
          end
          chapter.check_pages << comm_link
          LOG.debug "Added to chapter check_pages: #{comm_link}"
        end
        
        chapter.pages = pages
        chapter.check_page_data = {}
        chapter.check_pages.each do |check_page|
          if has_cache?(check_page, where: 'temp')
            temp_data = down_or_cache(check_page, where: 'temp')
            save_down(check_page, temp_data, where: @group_folder)
          else
            down_or_cache(check_page, where: @group_folder)
          end
          if check_page != chapter.check_pages.first
            chapter.check_page_data_set(check_page, down_or_cache(check_page, where: @group_folder))
          end
        end
      end
      
      page_count = (comment_count < 50) ? 1 : (comment_count * 1.0 / 25).ceil
      msg_str = if @success
        "#{is_new ? 'New:' : 'Updated:'} #{chapter.title}: #{page_count} page#{page_count != 1 ? 's' : ''} (Got #{@download_count} page#{@download_count != 1 ? 's' : ''})"
      else
        "ERROR: #{chapter.title}: #{@error}"
      end
      if @success
        if block_given?
          yield msg_str
        elsif notify
          LOG.info msg_str
        end
      else
        LOG.error msg_str
      end
      return chapter
    end
    
    def get_moiety_by_profile(profile)
      return @moiety_cache[profile] if @moiety_cache.key?(profile)
      user_id = profile.gsub('_', '-')
      return @moiety_cache[user_id] if @moiety_cache.key?(user_id)
      
      moieties = []
      GlowficEpub.moieties.keys.each do |author|
        moieties << author if GlowficEpub.moieties[author].include?(profile) or GlowficEpub.moieties[author].include?(user_id)
      end
      
      icon_moiety = moieties * ' '
      (LOG.error "No moiety for #{profile}") if icon_moiety.empty?
      @moiety_cache[user_id] = icon_moiety
      icon_moiety
    end
    
    def set_face_cache(face)
      face_id = face.unique_id
      face_id = face_id[0..-2].strip if face_id.end_with?(',')
      user_profile = face_id.split('#').first
      user_hash = @face_cache[user_profile] || @face_cache[user_profile.gsub('_', '-')]
      if user_hash
        user_hash[face.keyword] = face
        user_hash[:default] = face if user_hash[:default].try(:unique_id) == face.unique_id
      end
      @chapter_list.replace_face(face)
      @face_url_cache[face.imageURL.sub(/https?:\/\//, '')] = face
      @face_id_cache[face_id] = face
    end
    def get_face_by_id(face_id, options={})
      try_chapterface = options.key?(:try_chapterface) ? options[:try_chapterface] : true
      face_id = face_id[0..-2].strip if face_id.end_with?(',')
      return @face_id_cache[face_id] if @face_id_cache.key?(face_id)
      face_url = options.key?(:face_url) ? options[:face_url] : (options.key?(:url) ? options[:url] : nil)
      if face_url
        face_url_noprot = face_url.sub(/https?:\/\//, '')
        return @face_url_cache[face_url_noprot] if @face_url_cache.key?(face_url_noprot)
      end
      if try_chapterface
        chapter_face = @chapter_list.try(:get_face_by_id, face_id)
        if chapter_face.present?
          @face_id_cache[face_id] = chapter_face
          @face_url_cache[(face_url || chapter_face.imageURL).sub(/https?:\/\//, '')] = chapter_face
          return chapter_face
        end
      end
      user_profile = face_id.split('#').first
      face_name = face_id.sub("#{user_profile}#", "")
      face_name = "default" if face_name == face_id
      face_name = "default" if face_name == "(Default)"
      @icon_page_errors = [] unless @icon_page_errors
      @icon_errors = [] unless @icon_errors
      
      return if @icon_page_errors.include?(user_profile)
      
      unless @face_cache.key?(user_profile) or @face_cache.key?(user_profile.gsub('_', '-'))
        user_id = user_profile.gsub('_', '-')
        
        icon_page = giri_or_cache("http://#{user_id}.dreamwidth.org/icons")
        LOG.debug "nokogiri'd icon page"
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
          params[:imageURL] = icon_src
          params[:author] = get_author_by_id(user_profile)
          
          icon_keywords.each do |keyword_element|
            keyword = keyword_element.text.strip
            keyword = keyword[0..-2].strip if keyword.end_with?(",")
            params[:keyword] = keyword
            params[:unique_id] = "#{user_id}##{params[:keyword]}"
            face = Face.new(params)
            icon_hash[params[:keyword]] = face
            @chapter_list.replace_face(face)
            if icon_element == default_icon
              icon_hash[:default] = face
              params[:author].default_face = face if params[:author] && !params[:author].default_face_id.present?
            end
            @face_param_cache[face.unique_id] = params
            @face_url_cache[icon_src.sub(/https?:\/\//, '')] = face
          end
        end
        
        LOG.debug "got #{icon_hash.keys.count} icon(s)"
        
        @face_cache[user_profile] = icon_hash
      end
      
      icons_hash = @face_cache[user_profile] || @face_cache[user_profile.gsub('_', '-')]
      @face_id_cache[face_id] = icons_hash[face_name] if icons_hash.key?(face_name)
      @face_id_cache[face_id] = icons_hash[:default] if (face_name.downcase == "default" or face_name == :default) and icons_hash.key?(:default)
      return @face_id_cache[face_id] if @face_id_cache.key?(face_id)
      
      if face_url
        face_url_noprot = face_url.sub(/https?:\/\//, '')
        return @face_url_cache[face_url_noprot] if @face_url_cache.key?(face_url_noprot)
      end
      
      LOG.error "Failed to find a face for user: #{user_profile} and face: #{face_name}" + (face_url.present? ? " and URL: #{face_url}" : '') unless @icon_errors.include?(face_id)
      @icon_errors << face_id unless @icon_errors.include?(face_id)
      return nil
    end
    def get_updated_face(face)
      return nil unless face
      return get_face_by_id(face.unique_id) if @face_param_cache.key?(face.unique_id)
      
      params = {}
      params[:face_url] = face.imageURL if face.imageURL.present?
      params[:try_chapterface] = false
      done_face = get_face_by_id(face.unique_id, params)
      face_hash = @face_param_cache[(done_face || face).unique_id]
      if face_hash.present?
        face.from_json! face_hash
      elsif done_face.present? && !@face_issue_cache.include?(face.unique_id)
        LOG.error "Face was created, param cache was not set. Face not updating despite being supposed to. #{face}"
        @face_issue_cache << face.unique_id
      end
      set_face_cache(face)
      
      face
    end
    
    def set_author_cache(author)
      author_id = author.unique_id.gsub('_', '-')
      author_id = author_id.sub("dreamwidth#", "") if author_id.start_with?("dreamwidth#")
      @author_id_cache[author_id] = author
    end
    def get_author_by_id(author_id, options={})
      author_id = author_id.gsub('_', '-')
      author_id = author_id.sub("dreamwidth#", "") if author_id.start_with?("dreamwidth#")
      return @author_id_cache[author_id] if @author_id_cache.key?(author_id)
      
      try_chapterauthor = options.key?(:try_chapterauthor) ? options[:try_chapterauthor] : true
      
      if try_chapterauthor
        chapter_author = @chapter_list.try(:get_author_by_id, "dreamwidth##{author_id}")
        if chapter_author.present?
          @author_id_cache[author_id] = chapter_author
          return chapter_author
        end
      end
      
      char_page = giri_or_cache("http://#{author_id}.dreamwidth.org/profile")
      LOG.debug "nokogiri'd profile page"
      
      params = {}
      params[:moiety] = get_moiety_by_profile(author_id)
      
      profile_summary = char_page.at_css('.profile table')
      profile_summary.css('th').each do |th_element|
        if th_element.text["Name:"]
          params[:name] = th_element.next_element.text.strip
        end
      end
      params[:screenname] = author_id
      params[:display] = (params.key?(:name) and params[:name].downcase != params[:screenname].downcase) ? "#{params[:name]} (#{params[:screenname]})" : "#{params[:screenname]}"
      params[:unique_id] = "dreamwidth##{author_id}"
      
      
      author = Author.new(params)
      @author_param_cache[author.unique_id] = params
      @author_id_cache[author_id] = author
    end
    def get_updated_author(author)
      return nil unless author
      return get_author_by_id(author.unique_id) if @author_param_cache.key?(author.unique_id)
      
      done_author = get_author_by_id(author.unique_id, try_chapterauthor: false)
      author_hash = @author_param_cache[author.unique_id]
      author.from_json! author_hash
      set_author_cache(author)
      
      author
    end
    
    def make_message(message_element, options = {})
      #message_element is .comment
      in_context = (options.key?(:in_context) ? options[:in_context] : true)
      message_attributes = options.key?(:message_attributes) ? options[:message_attributes] : msg_attrs
      
      Time.zone = 'UTC'
      
      message_id = message_element["id"].sub("comment-", "").sub("entry-", "")
      message_type = (message_element["id"]["entry"]) ? PostType::ENTRY : PostType::REPLY
      
      author_id = message_element.at_css('span.ljuser').try(:[], "lj:user")
      
      params = {}
      if message_attributes.include?(:edittime)
        edit_element = message_element.at_css('.edittime')
        if edit_element
          edit_text = edit_element.at_css(".datetime").text.strip
          params[:edittime] = DateTime.strptime(edit_text, "%Y-%m-%d %H:%M (%Z)")
          edit_element.remove
        end
      end
      
      message_content = message_element.at_css('.comment-content, .entry-content')
      params[:content] = message_content.inner_html
      params[:author] = get_author_by_id(author_id) if message_attributes.include?(:author)
      params[:id] = message_id
      params[:chapter] = @chapter
      
      if message_attributes.include?(:face)
        userpic = message_element.at_css('.userpic').try(:at_css, 'img')
        face_url = ""
        face_name = "default"
        if userpic and userpic["title"]
          if userpic["title"] != author_id
            face_name = userpic["title"].sub("#{author_id}: ", "").split(" (").first
          end
          if userpic["src"]
            face_url = userpic["src"]
          end
        end
        
        face_id = "#{author_id}##{face_name}"
        params[:face] = get_face_by_id(face_id, face_url: face_url)
        params[:face] = @chapter_list.get_face_by_id(face_id) if params[:face].nil?
        
        if params[:face].nil? and not face_url.empty?
          face_params = {}
          face_params[:imageURL] = face_url
          face_params[:author] = get_author_by_id(author_id) if message_attributes.include?(:author)
          face_params[:keyword] = face_name
          face_params[:unique_id] = face_id
          face = Face.new(face_params)
          @chapter_list.add_face(face)
          LOG.debug "Face replaced by backup face '#{face}' with URL: #{face_url}"
          params[:face] = face
        end
      end
      
      if message_type == PostType::ENTRY
        params[:entry_title] = message_element.at_css('.entry-title').text.strip
        
        if message_attributes.include?(:time)
          time_text = message_element.at_css('.datetime').text.strip
          time_text = time_text[1..-1].strip if time_text.start_with?("@")
          params[:time] = DateTime.strptime(time_text, "%Y-%m-%d %I:%M %P")
        end
        
        entry = Entry.new(params)
      else
        parent_link = message_element.at_css('.link.commentparent').try(:at_css, 'a')
        if parent_link
          parent_href = parent_link[:href]
          parent_id = "cmt" + get_url_param(parent_href, "thread")
          @replies.each do |reply|
            params[:parent] = reply if reply.id == parent_id
          end
        else
          params[:parent] = @chapter.entry
        end
        
        if message_attributes.include?(:time)
          time_text = message_element.at_css('.datetime').text.strip
          params[:time] = DateTime.strptime(time_text, "%Y-%m-%d %I:%M %P (%Z)")
        end
        
        reply = Comment.new(params)
      end
    end
    def get_replies(chapter, options = {}, &block)
      return nil unless self.handles?(chapter)
      notify = options.key?(:notify) ? options[:notify] : true
      
      return chapter.replies if already_processed(chapter, options, &block)
      
      pages = chapter.pages
      (LOG.error "Chapter (#{chapter.title}) has no pages" and return) if pages.nil? or pages.empty?
      
      @chapter = chapter
      @replies = []
      @reply_ids = []
      @reply_ids << -1 unless chapter.thread
      threadcmt = (chapter.thread ? "cmt#{chapter.thread}" : "")
      @reply_ids << threadcmt if chapter.thread
      LOG.debug "Thread comment: \"#{threadcmt}\"" if chapter.thread
      
      pages.each do |page_url|
        page = nil
        comments = nil
        @repeated_page_cache[@group_folder] ||= {}
        if @repeated_page_cache[@group_folder].key?(page_url)
          page = @repeated_page_cache[@group_folder][page_url][:page]
          comments = @repeated_page_cache[@group_folder][page_url][:comments]
        end
        page = get_undiscretioned(page_url, replace: false, where: @group_folder) unless page.present?
        unless page
          LOG.error "Page failed to load (discretion advised warning?)"
          break
        end
        page_content = page.at_css('#content')
        
        if @replies.empty?
          entry_element = page_content.at_css('.entry')
          entry = make_message(entry_element, message_attributes: message_attributes)
          chapter.entry = entry
        end
        
        page_no = get_url_param(page_url, 'page')
        
        comments = page_content.css('.comment-wrapper.full') unless comments.present?
        if @page_list.include?(page_url)
          @repeated_page_cache[@group_folder][page_url] = {page: page, comments: comments} unless @repeated_page_cache[@group_folder].key?(page_url)
        end
        comments.each do |comment|
          comment_element = comment.at_css('.comment')
          
          comment_link = comment_element.at_css('.link.commentpermalink').try(:at_css, 'a')
          comment_id = -1
          if comment_link
            comment_href = comment_link[:href]
            comment_id = "cmt" + get_url_param(comment_href, "thread")
          end
          
          parent_link = comment_element.at_css('.link.commentparent').try(:at_css, 'a')
          parent_id = -1
          if parent_link
            parent_href = parent_link[:href]
            parent_id = "cmt" + get_url_param(parent_href, "thread")
          end
          
          if (@reply_ids.include?(parent_id) or @reply_ids.include?(comment_id))
            reply = make_message(comment_element, message_attributes: message_attributes)
            if chapter.thread and reply.id == threadcmt
              LOG.debug "chapter.thread: '#{chapter.thread}'; reply.id: '#{reply.id}'; threadcmt: '#{threadcmt}'; comment_id: '#{comment_id}'; reply_ids.include?(comment_id): #{@reply_ids.include?(comment_id)}"
              LOG.debug "Found the chapter thread comment #{reply}. Setting its parent to the entry #{chapter.entry}."
              reply.parent = chapter.entry
            end
            reply.page_no = page_no if page_no
            @replies << reply
            @reply_ids << reply.id unless @reply_ids.include?(reply.id)
          end
        end
        @page_list << page_url
      end
      
      msg_str = "#{chapter.title}: parsed #{pages.length} page#{pages.length == 1 ? '' : 's'}"
      if block_given?
        yield msg_str
      elsif notify
        LOG.info msg_str
      end
      
      chapter.processed = message_attributes
      chapter.replies=@replies
    end
  end
  
  class ConstellationHandler < SiteHandler
    attr_reader :download_count
    def self.handles?(thing)
      return false if thing.nil?
      if thing.is_a?(GlowficEpub::Author)
        return thing.unique_id.start_with?('constellation#')
      else
        chapter_url = (thing.is_a?(GlowficEpub::Chapter)) ? thing.url : thing
        return false if chapter_url.nil? or chapter_url.empty?
        
        uri = URI.parse(chapter_url)
        return uri.host.end_with?("vast-journey-9935.herokuapp.com")
      end
    end
    def initialize(options = {})
      super options
      @face_id_cache = {} # {"6951" => "[is a face: ahein, imgur..., etc.]"}
      @face_param_cache = {}
      @face_issue_cache = [] #these helpful names ikr
      @author_id_cache = {}
      @author_param_cache = {}
      @char_page_cache = {}
      # When retrieved in get_face_by_id
      @moiety_cache = {}
      @char_user_map = {}
      @char_page_errors = []
    end
    
    def get_permalink_for(message)
      if message.post_type == PostType::ENTRY
        "https://vast-journey-9935.herokuapp.com/posts/#{message.id}"
      else
        "https://vast-journey-9935.herokuapp.com/replies/#{message.id}#reply-#{message.id}"
      end
    end
    def get_full(chapter, options = {})
      if chapter.is_a?(GlowficEpub::Chapter)
        params = {per_page: 500}
        chapter_url = set_url_params(clear_url_params(chapter.url), params)
      else
        chapter_url = chapter
      end
      return nil unless self.handles?(chapter_url)
      notify = options.key?(:notify) ? options[:notify] : true
      is_new = options.key?(:new) ? options[:new] : false
      
      page_urls = []
      params = {per_page: 500, page: 1}
      first_page = set_url_params(clear_url_params(chapter.url), params)
      first_page_stuff = giri_or_cache(first_page, where: @group_folder)
      first_page_content = first_page_stuff.at_css('#content')
      
      reply_count = first_page_content.try(:at_css, '.reply-count').try(:text).try(:strip)
      if reply_count
        page_count = (reply_count.to_f / params[:per_page]).ceil
      else
        page_count = 1
        params[:per_page] = :all
      end
      
      1.upto(page_count).each do |num|
        params[:page] = num
        this_page = set_url_params(clear_url_params(chapter.url), params)
        down_or_cache(this_page, where: @group_folder)
        page_urls << this_page
      end
      
      chapter.processed = false if chapter.is_a?(GlowficEpub::Chapter)
      
      return page_urls
    end
    def get_updated(chapter, options = {})
      return nil unless self.handles?(chapter)
      notify = options.key?(:notify) ? options[:notify] : true
      
      chapter.url = set_url_params(clear_url_params(chapter.url), {per_page: :all}) unless chapter.url["per_page=all"]
      
      is_new = true
      prev_pages = chapter.pages
      check_pages = chapter.check_pages
      if prev_pages and not prev_pages.empty?
        is_new = false
        
        @download_count = 0
        changed = false
        check_pages.each_with_index do |check_page, i|
          page_location = get_page_location(check_page, where: @group_folder)
          was_file = File.file?(page_location)
          
          page_old_data = get_page_data(check_page, replace: false, where: @group_folder)
          unless was_file
            LOG.debug "check page #{i}, #{check_page}, didn't exist in the group folder"
            changed = true
            break
          end
          page_new = giri_or_cache(check_page, where: 'temp')
          
          page_old = Nokogiri::HTML(page_old_data)
          page_cache = chapter.check_page_data[check_page]
          page_cache = Nokogiri::HTML(page_cache) if page_cache
          LOG.debug "nokogiri'd"
          chapter.check_page_data_set(check_page, page_old_data) unless page_cache
          
          old_content = page_old.at_css('#content')
          new_content = page_new.at_css('#content')
          cache_content = page_cache.at_css('#content') if page_cache
          
          changed = (old_content.inner_html != new_content.inner_html)
          if changed
            LOG.debug "check page #{i}, #{check_page}, was different"
            break
          end
          if page_cache && !changed
            changed2 = (old_content.inner_html != cache_content.inner_html)
            if changed2
              LOG.info "check page cache in JSON (#{i}, #{check_page}) was different. other cache wasn't. fixing."
              changed = changed2
              break
            end
          end
          LOG.debug "check page #{i} was not different"
        end
        
        LOG.debug "#{(not changed) ? 'not ': ''}changed!"
        
        pages_exist = true
        prev_pages.each_with_index do |page_url, i|
          page_loc = get_page_location(page_url, where: @group_folder)
          if not File.file?(page_loc)
            pages_exist = false
            LOG.error "Failed to find a file (page #{i}) for chapter #{chapter}. Will get again."
            break
          end
        end #Check if all the pages exist, in case someone deleted them
        
        if changed
          LOG.debug "Content is different for #{chapter}" 
        elsif pages_exist # and not changed
          msg_str = "#{chapter.title}: #{chapter.pages.length} page#{chapter.pages.length != 1 ? 's' : ''} (checked #{@download_count} page#{@download_count != 1 ? 's' : ''})"
          if block_given?
            yield msg_str
          elsif notify
            LOG.info msg_str
          end
          return chapter
        end
        
        is_new = false
        chapter.pages = pages = [chapter.url]
      end
      
      chapter.processed = false
      
      #Needs to be updated / hasn't been got
      @download_count = 0
      
      pages = get_full(chapter, options.merge({new: (not changed)}))
      
      chapter.pages = pages
      chapter.check_page_data = {}
      chapter.check_pages.each do |check_page|
        if has_cache?(check_page, where: 'temp')
          temp_data = down_or_cache(check_page, where: 'temp')
          save_down(check_page, temp_data, where: @group_folder)
        else
          down_or_cache(check_page, where: @group_folder)
        end
        chapter.check_page_data_set(check_page, down_or_cache(check_page, where: @group_folder))
      end
      
      msg_str = "#{is_new ? 'New' : 'Updated'}: #{chapter.title}: #{chapter.pages.length} page#{chapter.pages.length != 1 ? 's' : ''} (Got #{@download_count} page#{@download_count != 1 ? 's' : ''})"
      if block_given?
        yield msg_str
      elsif notify
        LOG.info msg_str
      end
      return chapter
    end
    
    def get_moiety_by_id(character_id)
      char_page = giri_or_cache("https://vast-journey-9935.herokuapp.com/characters/#{character_id}/", replace: false)
      LOG.debug "nokogiri'd profile page"
      
      breadcrumb1 = char_page.at_css('.flash.subber a')
      if breadcrumb1 and breadcrumb1.text.strip == "Characters"
        user_info = char_page.at_css('#header #user-info')
        user_info.at_css('img').try(:remove)
        username = user_info.text.strip
      else
        username = breadcrumb1.text.split("Characters").first.strip
        username = username[0..-3] if username.end_with?("'s")
      end
      moiety = username.gsub(/[^\w]/, '_')
      moiety
    end
    
    def set_face_cache(face)
      face_id = face.unique_id
      face_id = face_id.sub("constellation#", "") if face_id.start_with?("constellation#")
      icon_id = face_id.split('#').last
      character_id = face_id.sub("##{icon_id}", '')
      character_id = nil if character_id == face_id
      character_id = nil if character_id.blank?
      @face_id_cache[icon_id] = face
      
      @chapter_list.replace_face(face)
      @face_id_cache[face_id] = face if icon_id == 'none' and character_id.try(:start_with?, 'user#')
      @face_id_cache[face.unique_id] = face
      
      if character_id && @char_page_cache.key?(character_id)
        @char_page_cache[character_id][icon_id] = face
        icon_id = face.unique_id.sub("#{character_id}#", '')
      end
      face
    end
    def get_face_by_id(face_id, options={})
      try_chapterface = options.key?(:try_chapterface) ? options[:try_chapterface] : true
      face_id = face_id.sub("constellation#", "") if face_id.start_with?("constellation#")
      return @face_id_cache[face_id] if @face_id_cache.key?(face_id)
      
      icon_id = face_id.split('#').last
      return @face_id_cache[icon_id] if @face_id_cache.key?(icon_id) and face_id.split('#').first.strip.empty?
      character_id = face_id.sub("##{icon_id}", '')
      
      if try_chapterface
        chapter_face = @chapter_list.try(:get_face_by_id, face_id)
        if chapter_face.present?
          @face_id_cache[face_id] = chapter_face
          @face_id_cache[icon_id] = chapter_face unless @face_id_cache.key?(icon_id)
          return chapter_face
        end
      end
      
      character_id = nil if character_id == face_id
      character_id = nil if character_id.blank?
      
      if icon_id == "none" and character_id.try(:start_with?, 'user#')
        face_params = {}
        face_params[:imageURL] = nil
        face_params[:keyword] = "none"
        face_params[:unique_id] = "#{character_id}#none"
        face_params[:author] = get_author_by_id(character_id)
        face = Face.new(face_params)
        @chapter_list.replace_face(face)
        @face_param_cache[face.unique_id] = face_params
        @face_id_cache[face_id] = face
        return face
      end
      
      @icon_errors = [] unless @icon_errors
      
      if character_id and not @char_page_cache.key?(character_id) and not @char_page_errors.include?(character_id) and not character_id.start_with?("user#")
        char_page_url = "https://vast-journey-9935.herokuapp.com/characters/#{character_id}/"
        char_page = giri_or_cache(char_page_url)
        LOG.debug "nokogiri'd"
        char_page_c = char_page.at_css("#content")
        icons = char_page_c.css(".gallery-icon")
        
        breadcrumb1 = char_page.at_css('.flash.subber a')
        if breadcrumb1 and breadcrumb1.text.strip == "Characters"
          user_info = char_page.at_css('#header #user-info')
          user_url = user_info.at_css('a')["href"]
          user_id = user_url.split('users/').last
        elsif breadcrumb1
          user_id = breadcrumb1["href"].split('users/').last.split('/characters').first
        else
          LOG.error "No breadcrumb on char page for #{character_id}"
        end
        @char_user_map[character_id] = user_id
        
        character = get_author_by_id(character_id)
        
        if icons.nil? or icons.empty?
          LOG.error "No icons for character ##{character_id}."
          @char_page_errors << character_id
        else
          icon_hash = {}
          default_icon = char_page_c.at_css('.character-icon')
          if default_icon
            icons << default_icon
          else
            LOG.warn "No default icon for #{character_id}"
          end
          icons.each do |icon_element|
            icon_link = icon_element.at_css('a')
            icon_url = icon_link.try(:[], :href)
            icon_img = icon_link.at_css('img')
            icon_src = icon_img.try(:[], :src)
            
            (LOG.error "Failed to find an img URL on the icon page for character ##{character_id}" and next) if icon_src.nil? or icon_src.empty?
            
            icon_keyword = icon_img.try(:[], :title)
            icon_numid = icon_url.split("icons/").last if icon_url
            
            unless icon_numid
              LOG.error "Failed to find an icon's numeric ID on character page ##{character_id}?"
              icon_numid = "unknown"
            end
            
            params = {}
            params[:imageURL] = icon_src
            params[:author] = character
            params[:keyword] = icon_keyword
            params[:unique_id] = "#{character_id}##{icon_numid}"
            params[:chapter_list] = @chapter_list
            face = Face.new(params)
            icon_hash[icon_numid] = face
            @chapter_list.replace_face(face)
            if default_icon == icon_element
              icon_hash[:default] = face
              params[:author].default_face = face if params[:author] && !params[:author].default_face_id.present?
            end
            
            @face_id_cache[face.unique_id] = face
            @face_param_cache[face.unique_id] = params
          end
          LOG.debug "got #{icon_hash.keys.length} icon(s)"
          @char_page_cache[character_id] = icon_hash
        end
      end
      
      return @face_id_cache[face_id] if @face_id_cache.key?(face_id)
      return @face_id_cache[icon_id] if @face_id_cache.key?(icon_id)
      
      if character_id and @char_user_map.key?(character_id)
        user_id = @char_user_map[character_id]
        usergal_page_url = "https://vast-journey-9935.herokuapp.com/users/#{user_id}/galleries/"
        usergal_page = giri_or_cache(usergal_page_url)
        LOG.debug "nokogiri'd"
        
        icons = usergal_page.at_css('#content').css('.gallery-icon')
        icons.each do |icon_element|
          icon_link = icon_element.at_css('a')
          icon_url = icon_link.try(:[], :href)
          next unless icon_url
          icon_numid = icon_url.split("icons/").last if icon_url
          next unless icon_numid == icon_id
          
          icon_img = icon_link.at_css('img')
          icon_src = icon_img.try(:[], :src)
          
          (LOG.error "Failed to find an img URL on the icon page for user ##{user_id}" and next) if icon_src.nil? or icon_src.empty?
          
          icon_keyword = icon_img.try(:[], :title)
          
          unless icon_numid
            LOG.error "Failed to find an icon's numeric ID on user gallery page ##{user_id}?"
            icon_numid = "unknown"
          end
          
          params = {}
          params[:imageURL] = icon_src
          params[:author] = character
          params[:keyword] = icon_keyword
          params[:unique_id] = "#{character_id}##{icon_numid}"
          params[:chapter_list] = @chapter_list
          face = Face.new(params)
          
          @chapter_list.replace_face(face)
          @face_id_cache[face.unique_id] = face
          @face_param_cache[face.unique_id] = params
          
          LOG.debug "Found an icon for character #{character_id}: ID ##{icon_numid} (on userpage ##{user_id})"
        end
      end
      
      return @face_id_cache[face_id] if @face_id_cache.key?(face_id)
      
      icon_page = giri_or_cache("https://vast-journey-9935.herokuapp.com/icons/#{icon_id}/")
      LOG.debug "nokogiri'd"
      
      icon_img = icon_page.at_css('#content img')
      params = {}
      params[:imageURL] = icon_img.try(:[], :src)
      params[:keyword] = icon_img.try(:[], :title)
      params[:unique_id] = "constellation##{icon_id}"
      params[:chapter_list] = @chapter_list
      face = Face.new(params)
      @chapter_list.replace_face(face)
      @face_id_cache[icon_id] = face
      @face_param_cache[face.unique_id] = params
      
      return @face_id_cache[icon_id] if @face_id_cache.key?(icon_id)
      
      #Shouldn't ever occur? We just loaded the icon page; it's probably going to error before this
      #if there's no icon, or Face.new will complain about nil params?
      LOG.error "Failed to find a face for character: #{character_id} and face: #{icon_id}" unless @icon_errors.include?(face_id)
      @icon_errors << face_id unless @icon_errors.include?(face_id)
      return default
    end
    def get_updated_face(face)
      return nil unless face
      return get_face_by_id(face.unique_id) if @face_param_cache.key?(face.unique_id)
      
      done_face = get_face_by_id(face.unique_id, try_chapterface: false)
      
      face_hash = @face_param_cache[(done_face || face).unique_id] || @face_param_cache[(done_face || face).unique_id.sub('constellation#', '')]
      if face_hash.present?
        face.from_json! face_hash
      elsif done_face.present? && !@face_issue_cache.include?(face.unique_id)
        LOG.error "Face was created, param cache was not set. Face not updating despite being supposed to. #{face}"
        @face_issue_cache << face.unique_id
      end
      set_face_cache(face)
      
      face
    end
    
    def set_author_cache(author)
      character_id = author.unique_id
      character_id = character_id.sub("constellation#", "") if character_id.start_with?("constellation#")
      @author_id_cache[character_id] = author
      author
    end
    def get_author_by_id(character_id, options={})
      character_id = character_id.sub("constellation#", "") if character_id.start_with?("constellation#")
      return @author_id_cache[character_id] if @author_id_cache.key?(character_id)
      
      try_chapterauthor = options.key?(:try_chapterauthor) ? options[:try_chapterauthor] : true
      
      if try_chapterauthor
        chapter_author = @chapter_list.try(:get_author_by_id, "constellation##{character_id}")
        if chapter_author.present?
          @author_id_cache[character_id] = chapter_author
          return chapter_author
        end
      end
      
      if character_id.start_with?("user#")
        user_id = character_id.sub("user#", "")
        
        user_page_url = "https://vast-journey-9935.herokuapp.com/users/#{user_id}/"
        user_page = giri_or_cache(user_page_url)
        LOG.debug "nokogiri'd"
        user_page_c = user_page.at_css('#content')
        
        char_name = user_page_c.at_css('.username').try(:text).try(:strip)
        
        params = {}
        params[:moiety] = char_name
        params[:name] = char_name
        params[:display] = char_name
        params[:unique_id] = "constellation#user##{user_id}"
        
        author = Author.new(params)
        @author_id_cache["user##{user_id}"] = author
        @author_param_cache[author.unique_id] = params
        return author
      else
        char_page_url = "https://vast-journey-9935.herokuapp.com/characters/#{character_id}/"
        char_page = giri_or_cache(char_page_url)
        LOG.debug "nokogiri'd"
        char_page_c = char_page.at_css('#content')
        
        char_screen = char_page_c.at_css(".character-screenname").try(:text).try(:strip)
        char_name = char_page_c.at_css(".character-name").try(:text).try(:strip)
        char_display = char_name + ((char_screen.nil? or char_screen.downcase == char_name.downcase) ? "" : " (#{char_screen})")
        
        params = {}
        params[:moiety] = get_moiety_by_id(character_id)
        params[:name] = char_name
        params[:screenname] = char_screen
        params[:display] = char_display
        params[:unique_id] = "constellation##{character_id}"
        
        author = Author.new(params)
        @author_id_cache[character_id] = author
        @author_param_cache[author.unique_id] = params
        return author
      end
    end
    def get_updated_author(author)
      return nil unless author
      return get_author_by_id(author.unique_id) if @author_param_cache.key?(author.unique_id)
      
      done_author = get_author_by_id(author.unique_id, try_chapterauthor: false)
      author_hash = @author_param_cache[author.unique_id]
      author.from_json! author_hash
      set_author_cache(author)
      
      author
    end
    
    def make_message(message_element, options = {})
      #message_element is the ".post-container"
      message_attributes = options.key?(:message_attributes) ? options[:message_attributes] : msg_attrs
      
      Time.zone = 'Eastern Time (US & Canada)'
      
      message_anchor = message_element.at_css("> a[name]")
      if message_anchor
        message_id = message_anchor[:name].split("reply-").last
        message_type = PostType::REPLY
      else
        entry_title = message_element.parent.at_css('#post-title').try(:at_css, 'a')
        LOG.error "Couldn't find the post's title! Gah!" unless entry_title
        
        message_id = entry_title[:href].split('posts/').last
        message_type = PostType::ENTRY
      end
      
      author_element = message_element.at_css('.post-author').try(:at_css, 'a')
      author_name = author_element.text.strip
      author_id = author_element["href"].split("users/").last
      
      character_element = message_element.at_css('.post-character').try(:at_css, 'a')
      if character_element
        character_id = character_element["href"].split("characters/").last
        character_name = character_element.text.strip
      else
        character_id = "user##{author_id}"
        character_name = author_name
      end
      
      date_element = message_element.at_css('.post-footer')
      
      params = {}
      
      if message_attributes.include?(:time)
        create_date = date_element.at_css('.post-posted').try(:text).try(:strip)
        LOG.error "No create date for message ID ##{message_id}?" unless create_date
        if create_date
          params[:time] = Time.zone.parse(create_date).to_datetime
        end
      end
      if message_attributes.include?(:edittime)
        edit_date = date_element.at_css('.post-updated').try(:text).try(:strip)
        if edit_date
          params[:edittime] = Time.zone.parse(edit_date).to_datetime
        end
      end
      
      params[:content] = message_element.at_css('.post-content').inner_html.strip
      params[:author] = get_author_by_id(character_id) if message_attributes.include?(:author)
      params[:author_str] = author_name unless message_attributes.include?(:author)
      
      params[:id] = message_id
      params[:chapter] = @chapter
      
      if message_attributes.include?(:face)
        userpic = message_element.at_css('.post-icon').try(:at_css, 'img')
        face_url = ""
        face_name = "none"
        face_id = ""
        if userpic
          face_id = userpic.parent["href"].split("icons/").last
          face_url = userpic["src"]
          face_name = userpic["title"]
        end
        face_uniqid = [character_id, face_id].reject{|thing| thing.nil?} * '#'
        face_uniqid = "#{face_id}" if character_id == "user##{author_id}"
        params[:face] = get_face_by_id(face_uniqid) unless face_uniqid.empty?
        params[:face].author = params[:author] if params[:face]
        params[:face] = @chapter_list.get_face_by_id(face_uniqid) if params[:face].nil?
        
        if params[:face].nil? and not face_url.empty?
          face_params = {}
          face_params[:imageURL] = face_url
          face_params[:keyword] = face_name
          face_params[:unique_id] = face_id
          face_params[:author] = get_author_by_id(character_id)
          face = Face.new(face_params)
          @chapter_list.add_face(face)
          params[:face] = face
        end
      
        if params[:face].nil? and face_url.empty?
          face_params = {}
          face_params[:imageURL] = nil
          face_params[:keyword] = face_name
          face_params[:unique_id] = "#{character_id}##{face_name}"
          face_params[:author] = get_author_by_id(character_id)
          face = Face.new(face_params)
          @chapter_list.add_face(face)
          params[:face] = face
        end
      end
      
      if message_type == PostType::ENTRY
        params[:entry_title] = @entry_title
        
        entry = Entry.new(params)
        @previous_message = entry
      else
        params[:parent] = @previous_message if @previous_message
        
        reply = Comment.new(params)
        @previous_message = reply
      end
    end
    def get_replies(chapter, options = {}, &block)
      return nil unless self.handles?(chapter)
      notify = options.key?(:notify) ? options[:notify] : true
      
      return chapter.replies if already_processed(chapter, options, &block)
      
      pages = chapter.pages
      (LOG.error "Chapter (#{chapter.title}) has no pages" and return) if pages.nil? or pages.empty?
      
      @entry_title = nil
      @chapter = chapter
      @replies = []
      @notify_extras = []
      pages.each do |page_url|
        page = giri_or_cache(page_url, replace: false, where: @group_folder)
        LOG.debug "nokogiri'd"
        
        error = page.at_css('.error.flash')
        if error
          error_text = error.text
          if error_text["do not have permission"]
            (LOG.error("Chapter '#{chapter.title}': Error. Page was private!") and break)
          elsif error_text["not be found"]
            (LOG.error("Chapter '#{chapter.title}': Error. Post does not exist!") and break)
          elsif error_text["content warning"]
            # is a content warning; ignore
          else
            (LOG.error("Chapter '#{chapter.title}': Error. Unknown post error: '#{error_text}'") and break)
          end
        end
        
        page_content = page.at_css('#content')
        post_title = page.at_css('#post-title')
        (LOG.error("No post title; probably not a post") and break) unless post_title
        @entry_title = post_title.text.strip unless @entry_title
        
        @chapter.title_extras = page.at_css('.post-subheader').try(:text).try(:strip) if !@chapter.title_extras.present?
        
        if @replies.empty?
          @entry_element = page_content.at_css('.post-container.post-post')
          entry = make_message(@entry_element, message_attributes: message_attributes)
          chapter.entry = entry
        end
        
        comments = page_content.css('> .post-container.post-reply')
        comments.each do |comment_element|
          reply = make_message(comment_element, message_attributes: message_attributes)
          @replies << reply
        end
        
        if page_url == pages.last
          post_ender = page_content.at_css('.post-ender')
          if post_ender
            things = [chapter.entry] + @replies
            last_time = things.last.try(:time)
            if not last_time
              LOG.error "#{chapter.title}: ended but cannot get last_time. (???)"
            elsif post_ender.text.downcase['ends'] or post_ender.text.downcase['complete']
              old_time = chapter.time_completed
              chapter.time_completed = last_time
              
              @notify_extras << "completed on '#{date_display(chapter.time_completed)}'" + ((old_time && old_time != chapter.time_completed) ? " (old time: #{date_display(old_time)})" : "")
            elsif post_ender.text.downcase['hiatus']
              old_time = chapter.time_hiatus
              chapter.time_hiatus = last_time
              chapter.time_completed = nil if chapter.time_completed and chapter.time_hiatus >= chapter.time_completed
              
              @notify_extras << "hiatus on #{date_display(chapter.time_hiatus)}" + ((old_time && old_time != chapter.time_hiatus) ? " (old time: #{date_display(old_time)})" : "")
            else
              LOG.error "#{chapter.title}: ended non-hiatus non-complete on #{date_display(last_time)} (???)"
            end
          elsif chapter.time_completed or chapter.time_hiatus
            @notify_extras << "no ender; wiping" + (chapter.time_completed ? " completed #{date_display(chapter.time_completed)}" : '') + (chapter.time_hiatus ? " hiatus #{date_display(chapter.time_hiatus)}" : '')
            chapter.time_completed = nil
            chapter.time_hiatus = nil
          end
        end
      end
      
      pages_effectual = (@replies.length * 1.0 / 25).ceil
      pages_effectual = 1 if pages_effectual < 1
      
      msg_str = "#{chapter.title}: parsed #{pages_effectual} page#{pages_effectual == 1 ? '' : 's'}" + (@notify_extras.present? ? ", #{@notify_extras * ', '}" : '')
      if block_given?
        yield msg_str
      elsif notify
        LOG.info msg_str
      end
      chapter.processed = message_attributes
      chapter.replies=@replies
    end
  end
end
