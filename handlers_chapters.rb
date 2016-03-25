module GlowficChapterHandlers
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
          next unless chapter_url
          chapter_section = defaultCont
          if (chapter_url.nil? or chapter_url.empty?)
            next
          end
          
          chapter_url = standardize_chapter_url(chapter_url)
          
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
        return unless chapter_url
        chapter_thread = get_url_param(chapter_url, "thread")
        chapter_thread = nil unless chapter_thread
        
        chapter_url = standardize_chapter_url(chapter_url)
        
        prev_chapter_load = (@prev_chapter_loads[chapter_url] or 0)
        prev_chapter_page = (@prev_chapter_pages[chapter_url] or 0)
        
        chapter_details = GlowficEpub::Chapter.new(url: chapter_url, name: chapter_text, sections: section_list, page_count: prev_chapter_page, loaded: prev_chapter_load, thread: chapter_thread)
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
  
  class SandboxListHandler
    def initialize(options = {})
      @group = nil
      @group = options[:group] if options.key?(:group)
    end
    def toc_to_chapterlist(options = {}, &block)
      fic_toc_url = options[:fic_toc_url] if options.key?(:fic_toc_url)
      
      @prev_chapter_pages = get_prev_chapter_pages(@group)
      @prev_chapter_loads = get_prev_chapter_loads(@group)
      
      chapter_list = GlowficEpub::Chapters.new
      
      LOG.info "TOC Page: #{fic_toc_url}"
      fic_toc_data = get_page_data(fic_toc_url, replace: true)
      fic_toc = Nokogiri::HTML(fic_toc_data)
      
      entry = fic_toc.at_css(".entry-content")
      return nil unless entry
      
      potential_headings = entry.css('b')
      uber_headings = []
      potential_headings.each do |node|
        max_dist = 3
        test_node = node
        is_heading = false
        max_dist.times do |i|
          test_node = test_node.previous
          break unless test_node
          next unless test_node.text?
          is_heading = test_node.text[/\-{3,}/]
          is_heading = !!is_heading
        end
        next unless is_heading
        
        test_node = node
        is_heading = false
        max_dist.times do |i|
          test_node = test_node.next
          break unless test_node
          next unless test_node.text?
          is_heading = test_node.text[/\-{3,}/]
          is_heading = !!is_heading
        end
        uber_headings << node if is_heading
      end
      
      puts "Super headings: #{uber_headings * ', '}"
      
      potential_headings = entry.css('u')
      headings = []
      potential_headings.each do |node| 
        next if uber_headings.include?(node)
        top_level = node
        while top_level.parent != entry
          top_level = top_level.parent
        end
        next if uber_headings.include?(top_level)
        headings << top_level
      end
      puts "Headings: #{headings * ', '}"
      
      prev_superheading = nil
      prev_heading = nil
      links = entry.css('a')
      links.each do |link|
        chapter_link = link
        
        top_level = link
        while top_level.parent != entry
          top_level = top_level.parent
        end
        
        heading = nil
        superheading = nil
        heading_text = nil
        superheading_text = nil
        prev_element = top_level.previous
        while prev_element and superheading.nil?
          heading = prev_element if headings.include?(prev_element) and heading.nil?
          superheading = prev_element if uber_headings.include?(prev_element)
          prev_element = prev_element.previous
        end
        
        in_li = false
        if link.parent.name == "li" and heading.nil?
          parent = link.parent
          in_li = true
          while parent and parent != entry and parent.name != "ol" and parent.name != "ul"
            parent = parent.parent
          end
          if parent and parent != entry
            list = parent
            previous = list.previous
            while previous and previous.name != "i" and previous != superheading
              previous = previous.previous
            end
            if previous and previous != superheading
              heading_text = get_text_on_line(previous).strip
            end
          end
        end
        
        next if superheading.nil?
        
        superheading_text = get_text_on_line(superheading).strip
        heading_text = get_text_on_line(heading).strip if heading
        
        if superheading_text != prev_superheading
          prev_heading = nil
          prev_superheading = superheading_text
          puts "Superheading: #{superheading_text}"
        end
        if heading_text and heading_text != prev_heading
          prev_heading = heading_text
          puts "Heading: #{heading_text}"
        end
        
        chapter_text = get_text_on_line(chapter_link, stop_at: :a, backward: in_li).strip
        chapter_url = chapter_link.try(:[], :href)
        next unless chapter_url
        
        chapter_thread = get_url_param(chapter_url, "thread")
        chapter_thread = nil unless chapter_thread
        
        chapter_url = standardize_chapter_url(chapter_url)
        
        prev_chapter_load = (@prev_chapter_loads[chapter_url] or 0)
        prev_chapter_page = (@prev_chapter_pages[chapter_url] or 0)
        
        section_list = [superheading_text, heading_text]
        section_list.reject! {|thing| thing.nil? }
        
        chapter_details = GlowficEpub::Chapter.new(url: chapter_url, name: chapter_text, sections: section_list, page_count: prev_chapter_page, loaded: prev_chapter_load, thread: chapter_thread)
        if block_given?
          yield chapter_details
        end
        
        chapter_list << chapter_details
      end
      
      chapter_list
    end
  end
  
  ##
  #class HandlerTemplate
  #  def initialize(options = {})
  #    @group = nil
  #    @group = options[:group] if options.key?(:group)
  #  end
  #  def toc_to_chapterlist(options = {}, &block)
  #    fic_toc_url = options[:fic_toc_url] if options.key?(:fic_toc_url)
  #    
  #    @prev_chapter_pages = get_prev_chapter_pages(@group)
  #    @prev_chapter_loads = get_prev_chapter_loads(@group)
  #    
  #    chapter_list = GlowficEpub::Chapters.new
  #    
  #    LOG.info "TOC Page: #{fic_toc_url}"
  #    fic_toc_data = get_page_data(fic_toc_url, replace: true)
  #    fic_toc = Nokogiri::HTML(fic_toc_data)
  #    
  #    entry = fic_toc.at_css(".entry-content")
  #    return nil unless entry
  #
  #    chapter_link = entry.at_css('a')
  #    return unless chapter_link
  #    chapter_text = get_text_on_line(chapter_link).strip
  #    chapter_url = chapter_link.try(:[], :href)
  #    chapter_thread = get_url_param(chapter_url, "thread")
  #    chapter_thread = nil unless chapter_thread
  #    
  #    chapter_url = standardize_chapter_url(chapter_url)
  #    
  #    prev_chapter_load = (@prev_chapter_loads[chapter_url] or 0)
  #    prev_chapter_page = (@prev_chapter_pages[chapter_url] or 0)
  #
  #    section_list = ["no section"]
  #    
  #    chapter_details = GlowficEpub::Chapter.new(url: chapter_url, name: chapter_text, sections: section_list, page_count: prev_chapter_page, loaded: prev_chapter_load)
  #    if block_given?
  #      yield chapter_details
  #    end
  #    
  #    chapter_list << chapter_details
  #    
  #    chapter_list
  #  end
  #end
end
