module GlowficSiteHandlers
  require 'model_methods'
  require 'models'
  require 'uri'
  include GlowficEpubMethods
  
  class SiteHandler
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
      
      another_page = nil
      prev_pages = chapter.pages
      if prev_pages and not prev_pages.empty?
        first_page_url = prev_pages.first
        first_page_old_data = get_page_data(first_page_url, replace: false)
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
        
        LOG.debug "New page found for chapter #{chapter}" if another_page
        if pages_exist and not changed
          LOG.info "#{chapter.title}: #{chapter.pages.length} page#{chapter.pages.length != 1 ? 's' : ''}" if notify
          return chapter
        end
      end
      
      #Hasn't been done before, or it's outdated, or some pages were deleted; re-get.
      @download_count = 0
      pages = get_full(chapter, options.merge({new: (not changed)}))
      chapter.pages = pages
      LOG.info "-- #{chapter.title}: #{chapter.pages.length} page#{chapter.pages.length != 1 ? 's' : ''} (Got #{@download_count} page#{@download_count != 1 ? 's' : ''})" if notify
      return chapter
    end
  end
end
