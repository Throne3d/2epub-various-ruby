module GlowficSiteHandlers
  require 'model_methods'
  require 'models'
  require 'uri'
  include GlowficEpubMethods
  include GlowficEpub::PostType
  
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
      @group = nil
      @group = options[:group] if options.key?(:group)
      @group_folder = "web_cache"
      @group_folder += "/#{@group}" if @group
      @chapter_list = []
      @chapter_list = options[:chapters] if options.key?(:chapters)
      @chapter_list = options[:chapter_list] if options.key?(:chapter_list)
      @face_cache = {} #{"alicornutopia" => {"pen" => "(url)"}}
      @face_id_cache = {} #{"alicornutopia#pen" => "(url)"}
      # When retreived in get_face_by_id
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
      
      current_page_data = get_page_data(chapter_url, replace: true)
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
    
    def get_face_by_id(face_id)
      return @face_id_cache[face_id] if @face_id_cache.key?(face_id)
      user_profile = face_id.split('#').first
      face_name = face_id.sub("#{user_profile}#", "")
      face_name = "default" if face_name == face_id
      face_name = "default" if face_name == "(Default)"
      @icon_page_errors = [] unless @icon_page_errors
      
      return if @icon_page_errors.include?(user_profile)
      
      unless @face_cache.key?(user_profile) or @face_cache.key?(user_profile.gsub('_', '-'))
        user_id = user_profile.gsub('_', '-')
        
        moieties = []
        MOIETIES.keys.each do |author|
          moieties << author if MOIETIES[author].include?(user_profile) or MOIETIES[author].include?(user_id)
        end
        
        icon_moiety = moieties * ' '
        
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
          end
          if (icon_element == default_icon)
            params[:keyword] = "default"
            params[:unique_id] = "#{user_id}#default"
            face = Face.new(params)
            icon_hash[:default] = face
          end
        end
        
        @face_cache[user_profile] = icon_hash
      end
      
      icons_hash = @face_cache.key?(user_profile) ? @face_cache[user_profile] : @face_cache[user_profile.gsub('_', '-')]
      return icons_hash[face_name] if icons_hash.key?(face_name)
      return icons_hash[:default] if (face_name.downcase == "default" or face_name == :default) and icons_hash.key?(:default)
      
      (LOG.error "Failed to find a face for user: #{user_profile} and face: #{face_name}" and return nil)
    end
    
    def make_message(message_element, options = {})
      in_context = (options.key?(:in_context) ? options[:in_context] : true)
      
      message_id = message_element["id"].sub("comment-", "").sub("entry-", "")
      message_type = (message_element["id"]["entry"]) ? PostType::ENTRY : PostType::REPLY
      
      userpic = message_element.at_css(".userpic img")
      author_name = message_element.at_css('span.ljuser').try(:[], "lj:user")
      
      face_name = "default"
      if userpic and userpic["title"]
        if userpic["title"] != author_name
          face_name = userpic["title"].sub("#{author_name}: ", "").split(" (").first
        end
      end
      
      params = {}
      params[:site_handler] = self
      params[:content] = message_element.at_css('.entry-content, .comment-content').inner_html
      params[:face] = get_face_by_id("#{author_name}##{face_name}")
      params[:author] = author_name
      params[:id] = message_id
      
      if message_type == PostType::ENTRY
        params[:entry_title] = message_element.at_css('.entry-title').text.strip
        
        entry = Entry.new(params)
      else
        parent_link = message_element.at_css(".link.commentparent a")
        if parent_link
          parent_href = parent_link[:href]
          parent_id = get_url_param(parent_href, "thread")
          @replies.each do |reply|
            params[:parent] = reply if reply.id == parent_id
          end
        else
          params[:parent] = @chapter.entry
        end
        
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
        page_data = get_page_data(page_url, replace: false)
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
end
