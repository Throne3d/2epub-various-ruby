module GlowficIndexHandlers
  require 'model_methods'
  require 'models'
  include GlowficEpubMethods
  
  class IndexHandler
    def self.handles(*args)
      @handles = args
    end
    def self.handles?(thing)
      return false unless @handles
      return @handles.include?(thing)
    end
    def handles?(thing)
      return self.handles? thing
    end
    def get_chapter_titles(chapter_link, options = {})
      backward = true
      backward = options[:backward] if options.key?(:backward)
      
      chapter_text = get_text_on_line(chapter_link, stop_at: :a, backward: backward, forward: false).strip
      chapter_text_extras = get_text_on_line(chapter_link, stop_at: :a, backward: false, include_node: false).strip
      
      if (chapter_text.index("(") and chapter_text_extras.index(")")) or (chapter_text.index("[") and chapter_text_extras.index("]"))
        chapter_text = get_text_on_line(chapter_link, stop_at: :a, backward: backward).strip
        chapter_text_extras = ""
      end #If the thing's got brackets split between the text & extras, shove it together
      
      if (chapter_text_extras.index("(") == chapter_text_extras.length or chapter_text_extras.index("[") == chapter_text_extras.length)
        chapter_text_extras = chapter_text_extras[0..-2].strip
      end #If it ends in a start-bracket, remove it
      if (chapter_text_extras.index(")") == chapter_text_extras.length and not chapter_text_extras.index("(")) or (chapter_text_extras.index("]") == chapter_text_extras.length and not chapter_text_extras.index("["))
        chapter_text_extras = chapter_text_extras[0..-2].strip
      end #If it ends in an end-bracket, and there's not corresponding start bracket, remove it
      
      chapter_text_extras = nil if chapter_text_extras.empty?
      
      [chapter_text, chapter_text_extras]
    end
  end
  
  class CommunityHandler < IndexHandler
    handles :glowfic
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
          chapter_details = GlowficEpub::Chapter.new(url: chapter_url, title: chapter_title, sections: chapter_sections, page_count: prev_chapter_page, loaded: prev_chapter_load)
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
  
  class OrderedListHandler < IndexHandler
    handles :effulgence, :pixiethreads, :incandescence, :radon
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
        chapter_text = get_text_on_line(chapter_link, after: false).strip
        chapter_text_extras = get_text_on_line(chapter_link, include_node: false, before: false).strip
        chapter_text_extras = nil if chapter_text_extras.empty?
        chapter_url = chapter_link.try(:[], :href)
        return unless chapter_url
        chapter_thread = get_url_param(chapter_url, "thread")
        chapter_thread = nil unless chapter_thread
        
        chapter_url = standardize_chapter_url(chapter_url)
        
        prev_chapter_load = (@prev_chapter_loads[chapter_url] or 0)
        prev_chapter_page = (@prev_chapter_pages[chapter_url] or 0)
        
        chapter_details = GlowficEpub::Chapter.new(url: chapter_url, title: chapter_text, title_extras: chapter_text_extras, sections: section_list, page_count: prev_chapter_page, loaded: prev_chapter_load, thread: chapter_thread)
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
          subsection_text.strip!
          subsection_text = i.to_s if subsection_text.empty?
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
      
      previous_sections = []
      each_section(entry, []) do |section, section_list|
        get_chapters(section, section_list) do |chapter_details|
          chapter_list << chapter_details
          sections = chapter_details.sections
          sections.each_with_index do |section, i|
            if previous_sections.length <= i or previous_sections[i] != section
              puts "Section (depth #{i+1}): #{section}"
            end
          end
          previous_sections = sections
          if block_given?
            yield chapter_details
          end
        end
      end
      
      chapter_list
    end
  end
  
  class SandboxListHandler < IndexHandler
    handles :sandbox
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
        
        chapter_text, chapter_text_extras = get_chapter_titles(chapter_link, backward: in_li)
        
        chapter_url = chapter_link.try(:[], :href)
        next unless chapter_url
        
        chapter_thread = get_url_param(chapter_url, "thread")
        chapter_thread = nil unless chapter_thread
        
        chapter_url = standardize_chapter_url(chapter_url)
        
        prev_chapter_load = (@prev_chapter_loads[chapter_url] or 0)
        prev_chapter_page = (@prev_chapter_pages[chapter_url] or 0)
        
        section_list = [superheading_text, heading_text]
        section_list.reject! {|thing| thing.nil? }
        
        chapter_details = GlowficEpub::Chapter.new(url: chapter_url, title: chapter_text, title_extras: chapter_text_extras, sections: section_list, page_count: prev_chapter_page, loaded: prev_chapter_load, thread: chapter_thread)
        if block_given?
          yield chapter_details
        end
        
        chapter_list << chapter_details
      end
      
      chapter_list
    end
  end
  
  class NeatListHandler < IndexHandler
    handles :marri, :peterverse, :maggie
    def initialize(options = {})
      @group = nil
      @group = options[:group] if options.key?(:group)
      
      @heading1select = "b, strong"
      @heading2select = "u"
      @heading3select = "em, i"
      if @group == :maggie
        @heading1select = "u"
        @heading2select = "b, strong"
      end
    end
    def entry
      @entry
    end
    def get_heading_encapsule(node)
      text = get_text_on_line(node).strip
      node_text = node.text.strip
      return if not text or not node_text or text.empty? or node_text.empty? or text.index(node_text) > 0
      
      parenter = node
      while parenter and parenter != @entry and parenter.name != "li"
        parenter = parenter.parent
      end
      return unless parenter == @entry
      
      encapsule = node
      while encapsule and encapsule.parent and encapsule.parent.text == encapsule.text and encapsule.parent != @entry
        encapsule = encapsule.parent
      end
      return (encapsule or node)
    end
    def toc_to_chapterlist(options = {}, &block)
      fic_toc_url = options[:fic_toc_url] if options.key?(:fic_toc_url)
      
      @prev_chapter_pages = get_prev_chapter_pages(@group)
      @prev_chapter_loads = get_prev_chapter_loads(@group)
      
      chapter_list = GlowficEpub::Chapters.new
      
      LOG.info "TOC Page: #{fic_toc_url}"
      fic_toc_data = get_page_data(fic_toc_url, replace: true)
      fic_toc = Nokogiri::HTML(fic_toc_data)
      
      @entry = fic_toc.at_css(".entry-content")
      return nil unless entry
      
      links = entry.css('a')
      #Bold, underlined, italics
      #Tiers of heading ^
      potential_heading1s = entry.css(@heading1select)
      potential_heading2s = entry.css(@heading2select)
      potential_heading3s = entry.css(@heading3select)
      
      heading1s = []
      heading2s = []
      heading3s = []
      
      potential_heading1s.each do |node|
        encapsule = get_heading_encapsule(node)
        next unless encapsule
        heading1s << encapsule
      end
      potential_heading2s.each do |node|
        encapsule = get_heading_encapsule(node)
        next unless encapsule
        heading2s << encapsule
      end
      potential_heading3s.each do |node|
        encapsule = get_heading_encapsule(node)
        next unless encapsule
        heading3s << encapsule
      end
      
      heading3s = [] if (heading3s - heading1s).empty?
      heading3s = [] if (heading3s - heading2s).empty?
      heading2s = [] if (heading2s - heading1s).empty?
      
      
      if heading2s.length < 1
        heading2s = heading3s
        heading3s = []
      end
      if heading1s.length < 1
        heading1s = heading2s
        heading2s = []
      end
      puts "Headings #1: #{heading1s.length}"
      puts "#{heading1s * ', '}" unless heading1s.empty?
      puts "Headings #2: #{heading2s.length}"
      puts "#{heading2s * ', '}" unless heading2s.empty?
      puts "Headings #3: #{heading3s.length}"
      puts "#{heading3s * ', '}" unless heading3s.empty?
      
      prev_heading1 = nil
      prev_heading2 = nil
      prev_heading3 = nil
      links.each do |link|
        chapter_link = link
        
        
        top_level = link
        while top_level.parent != entry
          top_level = top_level.parent
        end
        
        heading1 = nil
        heading2 = nil
        heading3 = nil
        heading1_text = nil
        heading2_text = nil
        heading3_text = nil
        prev_element = top_level.previous
        while prev_element and heading1.nil?
          heading3 = prev_element if heading3s.include?(prev_element) and heading3.nil? and heading2.nil?
          heading2 = prev_element if heading2s.include?(prev_element) and heading2.nil?
          heading1 = prev_element if heading1s.include?(prev_element)
          prev_element = prev_element.previous
        end
        
        next if heading1.nil?
        
        heading1_text = get_text_on_line(heading1).strip
        heading2_text = get_text_on_line(heading2).strip if heading2
        heading3_text = get_text_on_line(heading3).strip if heading3
        
        if heading1_text != prev_heading1
          prev_heading2 = nil
          prev_heading3 = nil
          prev_heading1 = heading1_text
          puts "Heading #1: #{heading1_text}"
        end
        if heading2_text != prev_heading2
          prev_heading3 = nil
          prev_heading2 = heading2_text
          puts "Heading #2: #{heading2_text}"
        end
        if heading3_text != prev_heading3
          prev_heading3 = heading3_text
          puts "Heading #3: #{heading3_text}"
        end
        
        chapter_text = get_text_on_line(chapter_link, stop_at: :a).strip
        chapter_url = chapter_link.try(:[], :href)
        next unless chapter_url
        
        chapter_thread = get_url_param(chapter_url, "thread")
        chapter_thread = nil unless chapter_thread
        
        chapter_url = standardize_chapter_url(chapter_url)
        
        prev_chapter_load = (@prev_chapter_loads[chapter_url] or 0)
        prev_chapter_page = (@prev_chapter_pages[chapter_url] or 0)
        
        section_list = [heading1_text, heading2_text, heading3_text]
        section_list.reject! {|thing| thing.nil? }
        
        chapter_details = GlowficEpub::Chapter.new(url: chapter_url, title: chapter_text, sections: section_list, page_count: prev_chapter_page, loaded: prev_chapter_load, thread: chapter_thread)
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
  #    #next unless chapter_url
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
  #    chapter_details = GlowficEpub::Chapter.new(url: chapter_url, title: chapter_text, sections: section_list, page_count: prev_chapter_page, loaded: prev_chapter_load)
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
