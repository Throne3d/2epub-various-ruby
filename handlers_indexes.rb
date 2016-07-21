module GlowficIndexHandlers
  require 'model_methods'
  require 'models'
  include GlowficEpubMethods
  
  class IndexHandler
    attr_reader :group
    def initialize(options = {})
      @group = options[:group] if options.key?(:group)
      @chapter_list = options[:chapter_list] if options.key?(:chapter_list)
    end
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
    def chapter_list
      @chapter_list ||= GlowficEpub::Chapters.new
    end
    
    def persist_chapter_data(params)
      raise(ArgumentException, "params must be a hash") unless params.is_a?(Hash)
      url = params[:url]
      persists.each do |persist|
        next if persist[:if] && !params[persist[:if]]
        next if persist[:unless] && params[persist[:unless]]
        persist_data = get_prev_chapter_detail(group, detail: persist[:thing], only_present: true)
        next unless persist_data.key?(url)
        params[persist[:thing]] = persist_data[url]
      end
      params
    end
    def persists
      @persists = [
        {thing: :pages},
        {thing: :check_pages},
        {thing: :processed},
        {thing: :entry, :if => :processed},
        {thing: :replies, :if => :processed},
        {thing: :authors, :if => :processed},
        {thing: :entry_title, :if => :processed},
        {thing: :time_completed, :if => :processed},
        {thing: :time_hiatus, :if => :processed},
        {thing: :processed_epub, :if => :processed}
      ]
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
    def chapter_from_toc(params = {})
      params[:thread] = get_url_param(params[:url], "thread")
      params[:url] = standardize_chapter_url(params[:url])
      params.delete(:thread) unless params[:thread]
      params.delete(:title_extras) if params.key?(:title_extras) and (not params[:title_extras] or params[:title_extras].empty?)
      
      persist_chapter_data(params)
      return GlowficEpub::Chapter.new(params)
    end
  end
  
  class CommunityHandler < IndexHandler
    handles :glowfic
    def initialize(options = {})
      super(options)
    end
    def toc_to_chapterlist(options = {}, &block)
      fic_toc_url = options[:fic_toc_url] if options.key?(:fic_toc_url)
      
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
          chapter_title_extras = nil
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
          chapter_title_extras = "+" unless complete
          
          chapter_sections = (chapter_section) ? [chapter_section] : []
          chapter_details = chapter_from_toc(url: chapter_url, title: chapter_title, title_extras: chapter_title_extras, sections: chapter_sections)
          if block_given?
            yield chapter_details
          end
          
          chapter_list[chapter_section] = [] unless chapter_list.key? chapter_section
          chapter_list[chapter_section] << chapter_details
        end
      end
      continuities = chapter_list.keys.sort
      sorted_chapter_list = self.chapter_list
      
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
    handles :effulgence, :pixiethreads, :incandescence, :radon, :silmaril
    def initialize(options = {})
      super(options)
      @strip_li_end = (@group == :incandescence or @group == :silmaril)
      @strip_li_end = options[:strip_li_end] if options.key?(:strip_li_end)
    end
    def get_chapters(section, section_list, index=1, &block)
      #puts "Find chapters in (#{section_list}): #{section.text}"
      
      chapters = section.css('> ol > li')
      if chapters and not chapters.empty?
        chapters.each_with_index do |chapter, i|
          get_chapters(chapter, section_list, i, &block)
        end
      else
        chapter_link = section.at_css('> a')
        if chapter_link
          chapter_links = [chapter_link]
        else
          chapter_links = section.css("> ul > li a")
          return unless chapter_links.present?
          sublist = section.at_css('> ul')
          subsection_text = ""
          curr_element = sublist.previous
          while curr_element
            subsection_text = curr_element.text + subsection_text
            curr_element = curr_element.previous
          end
          subsection_text.strip!
          subsection_text = index.to_s if subsection_text.empty?
          section_list = section_list + [subsection_text]
        end
        
        chapter_links.each do |chapter_link|
          chapter_text = get_text_on_line(chapter_link, after: false).strip
          chapter_text_extras = get_text_on_line(chapter_link, include_node: false, before: false).strip
          open_count = chapter_text.scan("(").count - chapter_text.scan(")").count
          if open_count > 0 and chapter_text_extras.start_with?(")")
            chapter_text += ")"
            chapter_text_extras = chapter_text_extras[1..-1]
          end
          chapter_text_extras = nil if chapter_text_extras.empty?
          chapter_url = chapter_link.try(:[], :href)
          next unless chapter_url
          
          chapter_details = chapter_from_toc(url: chapter_url, title: chapter_text, title_extras: chapter_text_extras, sections: section_list)
          if block_given?
            yield chapter_details
          end
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
          yield section, section_list, i
        end
      end
    end
    def toc_to_chapterlist(options={}, &block)
      fic_toc_url = options[:fic_toc_url] if options.key?(:fic_toc_url)
      
      LOG.info "TOC Page: #{fic_toc_url}"
      fic_toc_data = get_page_data(fic_toc_url, replace: true)
      fic_toc_data = fic_toc_data.gsub("</li>", "") if @strip_li_end
      fic_toc = Nokogiri::HTML(fic_toc_data)
      
      entry = fic_toc.at_css(".entry-content")
      return nil unless entry
      
      previous_sections = []
      each_section(entry, []) do |section, section_list, section_index|
        get_chapters(section, section_list, section_index) do |chapter_details|
          chapter_list << chapter_details
          sections = chapter_details.sections
          sections.each_with_index do |section, i|
            if previous_sections.length <= i or previous_sections[i] != section
              LOG.info "- Section (depth #{i+1}): #{section}"
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
      super(options)
    end
    def toc_to_chapterlist(options = {}, &block)
      fic_toc_url = options[:fic_toc_url] if options.key?(:fic_toc_url)
      
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
        
        section_list = [superheading_text, heading_text]
        section_list.reject! {|thing| thing.nil? }
        
        chapter_details = chapter_from_toc(url: chapter_url, title: chapter_text, title_extras: chapter_text_extras, sections: section_list)
        if block_given?
          yield chapter_details
        end
        
        chapter_list << chapter_details
      end
      
      chapter_list
    end
  end
  
  class NeatListHandler < IndexHandler
    handles :marri, :peterverse, :maggie, :throne
    attr_reader :entry
    def initialize(options = {})
      super(options)
      @heading_selects = ["b, strong", "u", "em, i"]
      if group == :maggie
        @heading_selects[0] = "u"
        @heading_selects[1] = "b, strong"
      elsif group == :throne
        @heading_selects = ["h4", "h5"]
      end
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
      
      LOG.info "TOC Page: #{fic_toc_url}"
      fic_toc_data = get_page_data(fic_toc_url, replace: true)
      fic_toc = Nokogiri::HTML(fic_toc_data)
      
      @entry = fic_toc.at_css(".entry-content")
      return nil unless entry
      
      links = entry.css('a')
      #Bold, underlined, italics
      #Tiers of heading ^
      potential_headings = []
      @heading_selects.each_with_index do |heading_select, i|
        potential_headings[i] = entry.css(heading_select)
      end
      
      headings = []
      
      potential_headings.each_with_index do |potential_heading, i|
        headings[i] = []
        potential_heading.each do |node|
          encapsule = get_heading_encapsule(node)
          next unless encapsule
          headings[i] << encapsule
        end
      end
      
      if (headings.length > 1)
        (headings.length-1).downto(1).each do |i|
          (i-1).downto(0).each do |y|
            headings[i] = [] if (headings[i] - headings[y]).empty?
          end
        end
      end
      heading_levels = headings.reject {|item| item.empty?}
      
      prev_headings = [nil] * heading_levels.length
      links.each do |link|
        chapter_link = link
        
        top_level = link
        while top_level.parent != entry
          top_level = top_level.parent
        end
        
        heading = []
        heading_text = []
        prev_element = top_level.previous
        if (not heading_levels.empty?)
          while prev_element and (heading.empty? or heading[0].nil?)
            (heading_levels.length-1).downto(0).each do |i|
              supers_nil = true
              (i).downto(0).each do |y|
                unless heading[y].nil?
                  supers_nil = false
                  break
                end
              end
              heading[i] = prev_element if supers_nil and heading_levels[i].include?(prev_element)
            end
            prev_element = prev_element.previous
          end
        end
        
        next if (heading.empty? or heading[0].nil?) and not heading_levels.empty?
        
        heading.each_with_index do |node, i|
          heading_text[i] = get_text_on_line(node).strip if node
        end
        
        heading_text.each_with_index do |text, i|
          if text != prev_headings[i]
            (i).upto(heading_text.length-1).each do |y|
              prev_headings[y] = nil
            end
            prev_headings[i] = text
            puts "Heading ##{i}: #{text}"
          end
        end
        
        chapter_text, chapter_text_extras = get_chapter_titles(chapter_link)
        
        chapter_url = chapter_link.try(:[], :href)
        next unless chapter_url
        
        section_list = heading_text
        section_list.reject! {|thing| thing.nil? }
        
        chapter_details = chapter_from_toc(url: chapter_url, title: chapter_text, title_extras: chapter_text_extras, sections: section_list)
        if block_given?
          yield chapter_details
        end
        
        chapter_list << chapter_details
      end
      
      chapter_list
    end
  end
  
  class ConstellationIndexHandler < IndexHandler
    handles :constellation, :opalescence, :zodiac
    def initialize(options = {})
      super(options)
    end
    
    def fix_url_folder(url)
      url.sub(/(users|boards|galleries|characters)\/(\d+)(\?|$)/, '\1/\2/\3')
    end
    def get_absolute_url(url_path, current_url)
      if url_path.start_with?("/")
        url_path = "https://vast-journey-9935.herokuapp.com" + url_path
      elsif not url_path.start_with?("http://") and not url_path.start_with?("https://")
        url_path = File.join((current_url.split("/")[0..-2]) * '/', url_path)
      end
      url_path = fix_url_folder(url_path)
      url_path
    end
    
    def board_to_block(options = {}, &block)
      board_url = options[:board_url] if options.key?(:board_url)
      board_url = fix_url_folder(board_url)
      LOG.info "TOC Page: #{board_url}"
      
      board_toc_data = get_page_data(board_url, replace: true, headers: {"Accept" => "text/html"})
      board_toc = Nokogiri::HTML(board_toc_data)
      
      content = board_toc.at_css('#content')
      board_sections = content.css('tbody tr th')
      
      board_title_ele = content.at_css('tr th')
      board_title_ele.at_css("a").try(:remove)
      board_name = board_title_ele.text.strip
      
      pages = board_toc.at_css('.pagination')
      last_url = board_url
      if pages
        pages.at_css('a.last_page').try(:remove)
        pages.at_css('a.next_page').try(:remove)
        last_url = get_absolute_url(pages.css('a').last[:href].strip, board_url)
      end
      
      previous_url = last_url
      while previous_url
        puts "URL: #{previous_url}"
        board_toc_data = get_page_data(previous_url, replace: (previous_url != board_url), headers: {"Accept" => "text/html"})
        board_toc = Nokogiri::HTML(board_toc_data)
        board_body = board_toc.at_css('tbody')
        
        chapter_sections = [board_name]
        
        chapters = board_body.css('tr')
        chapters = chapters.reverse unless board_sections
        chapters.each do |chapter_row|
          thead = chapter_row.at_css('th')
          next if thead and not thead.try(:[], :colspan)
          
          no_post = chapter_row.at_css('.centered.padding-10')
          next if no_post and no_post.text["No posts"]
          
          if thead
            section_name = thead.at_css('a').try(:text).try(:strip)
            chapter_sections = [board_name, section_name] if section_name
            LOG.error "couldn't get section name for thead #{thead}" unless section_name
            next
          end
          
          chapter_link = chapter_row.at_css('td a')
          chapter_title = chapter_link.text.strip
          chapter_url = get_absolute_url(chapter_link["href"], board_url)
          
          chapter_details = chapter_from_toc(url: chapter_url, title: chapter_title, sections: chapter_sections)
          
          if block_given?
            yield chapter_details
          end
        end
        
        temp_url = previous_url
        previous_url = board_toc.at_css('.pagination a.previous_page').try(:[], :href)
        previous_url = get_absolute_url(previous_url.strip, temp_url) if previous_url
      end
    end
    
    def userlist_to_block(options = {}, &block)
      user_url = options[:user_url] if options.key?(:user_url)
      user_url = fix_url_folder(user_url)
      LOG.info "TOC Page: #{user_url}"
      user_toc_data = get_page_data(user_url, replace: true, headers: {"Accept" => "text/html"})
      user_toc = Nokogiri::HTML(user_toc_data)
      
      content = user_toc.at_css('#content')
      
      pages = user_toc.at_css('.pagination')
      last_url = user_url
      if pages
        pages.at_css('a.last_page').try(:remove)
        pages.at_css('a.next_page').try(:remove)
        last_url = get_absolute_url(pages.css('a').last[:href].strip, user_url)
      end
      
      previous_url = last_url
      while previous_url
        puts "URL: #{previous_url}"
        user_toc_data = get_page_data(previous_url, replace: (previous_url != user_url), headers: {"Accept" => "text/html"})
        user_toc = Nokogiri::HTML(user_toc_data)
        user_body = user_toc.at_css('tbody')
        
        chapters = user_body.css('tr')
        chapters = chapters.reverse
        chapters.each do |chapter_row|
          thead = chapter_row.at_css('th')
          next if thead
          
          no_post = chapter_row.at_css('.centered.padding-10')
          next if no_post and no_post.text["No posts"]
          
          chapter_link = chapter_row.at_css('td a')
          chapter_title = chapter_link.text.strip
          chapter_url = get_absolute_url(chapter_link["href"], user_url)
          chapter_sections = chapter_row.at_css('.post-board').try(:text).try(:strip)
          
          chapter_details = chapter_from_toc(url: chapter_url, title: chapter_title, sections: chapter_sections)
          
          if block_given?
            yield chapter_details
          end
        end
        
        temp_url = previous_url
        previous_url = user_toc.at_css('.pagination a.previous_page').try(:[], :href)
        previous_url = get_absolute_url(previous_url.strip, temp_url) if previous_url
      end
    end
    
    def toc_to_chapterlist(options = {}, &block)
      fic_toc_url = options[:fic_toc_url] if options.key?(:fic_toc_url)
      fic_toc_url = fix_url_folder(fic_toc_url)
      
      if fic_toc_url.end_with?("/boards/")
        LOG.info "TOC Page: #{fic_toc_url}"
        fic_toc_data = get_page_data(fic_toc_url, replace: true)
        fic_toc = Nokogiri::HTML(fic_toc_data)
        
        boards = fic_toc.css("#content tr")
        boards.each do |board|
          next if board.at_css("th")
          
          board_link = board.at_css('a')
          board_name = board_link.text.strip
          next if board_name == "Site testing" or board_name == "Effulgence" or board_name == "Witchlight"
          board_url = get_absolute_url(board_link["href"], fic_toc_url)
          
          board_to_block(board_url: board_url) do |chapter_details|
            chapter_list << chapter_details
            if block_given?
              yield chapter_details
            end
          end
        end
      elsif fic_toc_url[/\/boards\/\d+/]
        board_to_block(board_url: fic_toc_url) do |chapter_details|
          chapter_list << chapter_details
          if block_given?
            yield chapter_details
          end
        end
      elsif fic_toc_url[/\/users\/\d+/]
        chapter_list.sort_chapters = true
        userlist_to_block(user_url: fic_toc_url) do |chapter_details|
          chapter_list << chapter_details
          if block_given?
            yield chapter_details
          end
        end
      else
        raise(ArgumentException, "Chapter URL is not /boards or /boards/:id or /users/:id – failed")
      end
      chapter_list
    end
  end
  
  class TestIndexHandler < IndexHandler
    handles :test, :temp_starlight, :lintamande, :report, :mwf_leaf, :mwf_lioncourt
    def initialize(options = {})
      super(options)
    end
    def toc_to_chapterlist(options = {}, &block)
      list = if @group == :test
        [
          {url: "https://vast-journey-9935.herokuapp.com/posts/43",
          title: "Book of Discovery",
          sections: ["Zodiac", "Book of the Moon"]},
          {url: "https://vast-journey-9935.herokuapp.com/posts/50",
          title: "Book of Experience",
          sections: ["Zodiac", "Book of the Moon"]},
          {url: "https://vast-journey-9935.herokuapp.com/posts/53",
          title: "A fresh start",
          sections: ["Zodiac", "Apricum"]},
          {url: "http://alicornutopia.dreamwidth.org/25861.html?style=site",
          title: "Double Witch",
          sections: ["Bluebell Flames"]},
          {url: "http://alicornutopia.dreamwidth.org/4027.html?style=site",
          title: "Clannish",
          sections: ["Incandescence", "Chamomile"]},
          {url: "https://alicornutopia.dreamwidth.org/6744.html?thread=2465368&style=site#cmt2465368",
          title: "A Joker summons Demon Cam",
          sections: ["Demon Cam"],
          title_extras: "(with kappa)"},
          {url: "https://alicornutopia.dreamwidth.org/6744.html?style=site&thread=2560344#cmt2560344",
          title: "Darren summons Demon Cam",
          sections: ["Demon Cam"],
          title_extras: "(with Aestrix)"}
        ]
      elsif @group == :temp_starlight
        [
          {url: "https://alicornutopia.dreamwidth.org/29069.html?style=site",
          title: "and in my hands place honesty",
          sections: ["Starlight"]},
          {url: "https://alicornutopia.dreamwidth.org/29401.html?style=site",
          title: "veritable",
          sections: ["Starlight"]}
        ]
      elsif @group == :lintamande
        [
          {url: "http://alicornutopia.dreamwidth.org/29664.html",
          title: "leave of absence",
          sections: ["Silmaril", "Elentári"]},
          {url: "http://lintamande.dreamwidth.org/381.html",
          title: "halls of stone",
          sections: ["Silmaril", "Elentári"]},
          {url: "http://alicornutopia.dreamwidth.org/30911.html",
          title: "spear of ice",
          sections: ["Silmaril", "Elentári"]},
          {url: "http://alicornutopia.dreamwidth.org/31535.html",
          title: "galaxy of stars",
          sections: ["Silmaril", "Elentári"]},
          {url: "http://alicornutopia.dreamwidth.org/29954.html",
          title: "interplanar studies",
          sections: ["Silmaril", "Telperion"]},
          {url: "http://alicornutopia.dreamwidth.org/30387.html",
          title: "applied theology",
          sections: ["Silmaril", "Telperion"]},
          {url: "http://alicornutopia.dreamwidth.org/31134.html",
          title: "high-energy physics",
          sections: ["Silmaril", "Telperion"]},
          {url: "http://lintamande.dreamwidth.org/513.html",
          title: "don't touch me",
          sections: ["Silmaril", "Promise in Arda"]},
          {url: "http://alicornutopia.dreamwidth.org/31354.html",
          title: "Kib in Valinor",
          sections: ["Silmaril", "Shine"]}
        ]
      end
      
      if @group == :report
        report_json = ""
        @group_folder = "web_cache/#{@group}"
        url = REPORT_LIST_URL
        file_path = get_page_location(url, where: @group_folder)
        if File.file?(file_path)
          open(file_path) do |old|
            text = old.read
            if text.strip.length > 10
              open(file_path + '.bak', 'w') do |new|
                new.write text
              end
            end
          end
        end
        report_json = get_page_data(url, where: @group_folder, replace: true).strip
        list = JSON.parse(report_json)
        list.each do |thing|
          thing.keys.each do |key|
            next unless key.is_a?(String)
            thing[key.to_sym] = thing[key]
            thing.delete(key)
          end
        end
      elsif @group == :mwf_leaf || @group == :mwf_lioncourt
        fic_toc_url = options[:fic_toc_url] if options.key?(:fic_toc_url)
        
        LOG.info "TOC Page: #{fic_toc_url}"
        fic_toc_data = get_page_data(fic_toc_url, replace: true)
        fic_toc = Nokogiri::HTML(fic_toc_data)
        
        list = []
        msg = fic_toc.at_css('.post.first').try(:at_css, '.message')
        if msg
          if @group == :mwf_leaf
            msg.css('> ul > li').each do |li|
              if li.at_css('ul')
                li.css('ul li a').each do |li_a|
                  url = li_a[:href]
                  if url["redirect.viglink.com"]
                    url = url.split('&u=').last.gsub('%3A', ':').gsub('%3F', '?').gsub('%3D', '=').gsub('%26', '&')
                  end
                  name = li_a.text.strip
                  sections = ["Lioncourt's coronation party"]
                  list << {url: url, title: name, sections: sections}
                end
              elsif li.at_css('a')
                li_a = li.at_css('a')
                url = li_a[:href]
                if url["redirect.viglink.com"]
                  url = url.split('&u=').last.gsub('%3A', ':').gsub('%3F', '?').gsub('%3D', '=').gsub('%26', '&')
                end
                name = li_a.text.strip
                list << {url: url, title: name}
              end
            end
          elsif @group == :mwf_lioncourt
            prev_url = ""
            msg.css('a').each do |anchor|
              url = anchor[:href]
              if url["redirect.viglink.com"]
                url = url.split('&u=').last.gsub('%3A', ':').gsub('%3F', '?').gsub('%3D', '=').gsub('%26', '&')
              end
              name = anchor.text.strip
              if prev_url.present? and url.sub('http://', '').sub('https://', '').start_with?(prev_url.sub('http://', '').sub('https://', '').sub(/[&\?]style=site/, '').sub(/[&\?]view=flat/, ''))
                puts "Skipping #{name} because thread of previous"
              elsif url.start_with?('http')
                prev_url = url
                list << {url: url, title: name}
              end
            end
          end
        end
      elsif @group == :lintamande
        const_handler = ConstellationIndexHandler.new(group: @group)
        chapter_list.sort_chapters = true
        const_chapters = const_handler.toc_to_chapterlist(fic_toc_url: FIC_TOCS[@group]) do |chapter|
          if block_given?
            yield chapter
          end
        end
        const_chapters.each do |chapter|
          chapter_list << chapter
        end
      end
      
      list.each do |item|
        chapter_details = chapter_from_toc(item)
        if block_given?
          yield chapter_details
        end
        chapter_list << chapter_details
      end
      
      return chapter_list
    end
  end
  
  ##
  #class HandlerTemplate < IndexHandler
  #  def initialize(options = {})
  #    super(options)
  #  end
  #  def toc_to_chapterlist(options = {}, &block)
  #    fic_toc_url = options[:fic_toc_url] if options.key?(:fic_toc_url)
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
  #    section_list = ["no section"]
  #    
  #    chapter_details = GlowficEpub::Chapter.new(url: chapter_url, title: chapter_text, sections: section_list)
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
