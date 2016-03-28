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
    def self.handles?(chapter)
      return false if chapter.nil? or chapter.url.nil? or chapter.url.empty?
      
      uri = URI.parse(chapter.url)
      return uri.host.end_with?("dreamwidth.org")
    end
    def initialize(options = {})
      @group = nil
      @group = options[:group] if options.key?(:group)
    end
    
    def get_next_page_link(current_page)
      partial_comments = current_page.css('.comment-thread .partial')
        
      if partial_comments.nil? or partial_comments.empty?
        return nil
      end
      
      partial_comment = partial_comments.first
      comment_link = partial_comment.at_css('h4.comment-title a')
      (LOG.warning "Issue finding link while processing chapter `#{chapter}`, comment #{partial_comment}" and return nil) if comment_link.nil? or not comment_link.try(:[], :href)
      
      new_url = comment_link.try(:[], :href)
      new_thread = get_url_param(new_url, "thread")
      params = {style: :site}
      params[:thread] = new_thread if new_thread
      (LOG.warning "No chapter thread?" and return nil) unless new_thread
      current_page_url = set_url_params(clear_url_params(new_url), params)
    end
    
    def get_full(chapter)
      return nil unless self.handles?(chapter)
      
      page_urls = []
      params = {style: :site}
      params[:thread] = chapter.thread if chapter.thread
      current_page_url = set_url_params(clear_url_params(chapter.url), params)
      
      while current_page_url
        page_urls << current_page_url
        current_page_data = get_page_data(current_page_url, replace: true)
        current_page = Nokogiri::HTML(current_page_data)
        
        current_page_url = get_next_page_link(current_page)
      end
      #LOG.info "Pages: #{page_urls.length}"
      chapter.pages = page_urls
      return chapter
    end
    
    def get_updated(chapter)
      return nil unless self.handles?(chapter)
      
      prev_pages = chapter.pages
      if prev_pages and not prev_pages.empty?
        last_page_url = prev_pages.last
        last_page_data = get_page_data(last_page_url, replace: true)
        last_page = Nokogiri::HTML(last_page_data)
        
        pages_exist = true
        prev_pages.each_with_index do |page_url, i|
          next if page_url == last_page_url
          page_loc = get_page_location(page_url)
          if not File.file?(page_loc)
            pages_exist = false
          end
        end #Check if all the pages exist, in case someone deleted them
        
        another_page = get_next_page_link(last_page)
        return chapter if pages_exist and not another_page
      end
      
      #Hasn't been done before, or it's outdated, or some pages were deleted; re-get.
      return get_full(chapter)
    end
  end
end
