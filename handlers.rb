module GlowficEpubHandlers
  require 'model_methods'
  include GlowficEpubMethods
  
  class CommunityHandler
    def initialize(options = {})
      @group = nil
      @group = options[:group] if options.key?(:group)
    end
    def toc_to_chapterlist(options = {}, &block)
      fic_toc_url = options[:fic_toc_url] if options.key?(:fic_toc_url)
      
      @prev_chapter_pages = get_prev_chapter_pages(@group)
      @prev_chapter_loads = get_prev_chapter_loads(@group)
      
      defaultCont = :"no continuity"
      chapter_list = {}
      
      while not fic_toc_url.nil? and fic_toc_url != ""
        LOG.info "TOC Page: #{fic_toc_url}"
        fic_toc_data = get_page_data(fic_toc_url, replace: true)
        fic_toc = Nokogiri::HTML(fic_toc_data)
        
        next_page_link = fic_toc.at_css(".navigation .month-forward a")
        fic_toc_url = nil
        if (next_page_link)
          fic_toc_url = next_page_link.try(:[], :href).try(:strip)
          #LOG.info "URL: #{fic_toc_url}"
        else
          LOG.info "No next page link"
        end
        
        entries = fic_toc.css("#archive-month .month .entry-title")
        entries.each do |entry|
          entry_box = entry.parent
          entry_link = entry.at_css('a')
          chapter_title = entry_link.try(:text)
          chapter_url = entry_link.try(:[], :href)
          chapter_section = defaultCont
          if (chapter_url.nil? or chapter_url.empty?)
            next
          end
          
          chapter_url = set_url_params(clear_url_params(chapter_url), {style: :site, view: :flat})
          
          chapter_tags = entry_box.css("div.tag ul li a")
          skip = false
          complete = false
          chapter_tags.each do |tag_link|
            tag_text = tag_link.text.strip
            if tag_text.downcase[0..10] == "continuity:"
              chapter_section = tag_text[12..-1].strip.to_sym
            end
            if tag_text.downcase[0..4] == "meta:"
              skip = true
              break
            end
            if tag_text.downcase[0..6] == "status:"
              if tag_text[": complete"]
                complete = true
              end
            end
          end
          
          if skip
            next
          end
          chapter_title += " +" unless complete
          prev_chapter_load = (@prev_chapter_loads[chapter_url] or 0)
          prev_chapter_page = (@prev_chapter_pages[chapter_url] or 0)
          
          chapter_sections = (chapter_section) ? [chapter_section] : []
          chapter_details = GlowficEpub::Chapter.new(url: chapter_url, name: chapter_title, sections: chapter_sections, page_count: prev_chapter_page, loaded: prev_chapter_load)
          if block_given?
            yield chapter_details
          end
          
          chapter_list[chapter_section] = [] unless chapter_list.key? chapter_section
          chapter_list[chapter_section] << chapter_details
        end
      end
      continuities = chapter_list.keys.sort
      sorted_chapter_list = GlowficEpub::Chapters.new
      
      continuities.each do |continuity|
        next if (continuity == defaultCont or continuity.downcase == "oneshot")
        chapter_list[continuity].each do |chapter|
          sorted_chapter_list << chapter
        end
      end
      
      if chapter_list.key?(defaultCont)
        chapter_list[defaultCont].each do |chapter|
          sorted_chapter_list << chapter
        end
      end
      if chapter_list.key?("oneshot")
        chapter_list[defaultCont].each do |chapter|
          sorted_chapter_list << chapter
        end
      end
      sorted_chapter_list
    end
  end
  
  class OrderedListHandler
    def initialize(options = {})
      @group = nil
      @group = options[:group] if options.key?(:group)
      @strip_li_end = @group == :incandescence
      @strip_li_end = options[:strip_li_end] if options.key?(:strip_li_end)
    end
    def get_chapters(section, section_list, &block)
      #More "get_chapter", but oh well.
      #puts "Find chapters in (#{section_list}): #{section.text}"
      
      chapters = section.css('> ol > li')
      if chapters and not chapters.empty?
        chapters.each do |chapter|
          get_chapters(chapter, section_list, &block)
        end
      else
        chapter_link = section.at_css('a')
        return unless chapter_link
        chapter_text = get_text_on_line(chapter_link).strip
        chapter_url = chapter_link.try(:[], :href)
        chapter_thread = get_url_param(chapter_url, "thread")
        chapter_thread = "" unless chapter_thread
        
        chapter_url = set_url_params(clear_url_params(chapter_url), {style: :site, view: :flat})
        
        prev_chapter_load = (@prev_chapter_loads[chapter_url] or 0)
        prev_chapter_page = (@prev_chapter_pages[chapter_url] or 0)
        
        chapter_details = GlowficEpub::Chapter.new(url: chapter_url, name: chapter_text, sections: section_list, page_count: prev_chapter_page, loaded: prev_chapter_load)
        if block_given?
          yield chapter_details
        end
      end
    end
    def each_section(node, section_list, &block)
      sections = node.css("> ol > li")
      i = 0
      sections.each do |section|
        i = i.next
        sublist = section.at_css('> ol')
        if sublist
          subsection_text = ""
          curr_element = sublist.previous
          while curr_element
            subsection_text = curr_element.text + subsection_text
            curr_element = curr_element.previous
          end
          subsection_text = i.to_s if subsection_text.empty?
          subsection_text.strip!
          each_section(section, section_list + [subsection_text], &block)
        else
          yield section, section_list
        end
      end
    end
    def toc_to_chapterlist(options={}, &block)
      fic_toc_url = options[:fic_toc_url] if options.key?(:fic_toc_url)
      
      @prev_chapter_pages = get_prev_chapter_pages(@group)
      @prev_chapter_loads = get_prev_chapter_loads(@group)
      
      chapter_list = GlowficEpub::Chapters.new
      
      LOG.info "TOC Page: #{fic_toc_url}"
      fic_toc_data = get_page_data(fic_toc_url, replace: true)
      fic_toc_data = fic_toc_data.gsub("</li>", "") if @strip_li_end
      fic_toc = Nokogiri::HTML(fic_toc_data)
      
      entry = fic_toc.at_css(".entry-content")
      return nil unless entry
      
      each_section(entry, []) do |section, section_list|
        get_chapters(section, section_list) do |chapter_details|
          chapter_list << chapter_details
          if block_given?
            yield chapter_details
          end
        end
      end
      
      chapter_list
    end
  end
end
