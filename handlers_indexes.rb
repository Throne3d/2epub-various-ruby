module GlowficIndexHandlers
  require 'scraper_utils'
  require 'models'
  include ScraperUtils

  INDEX_PRESETS = {
    test:
    [
      {url: "https://darkest-evening.dreamwidth.org/520.html?style=site",
      title: "You've Got Mail",
      sections: ["Incandescence"]},
      {url: "http://alicornutopia.dreamwidth.org/4027.html?style=site",
      title: "Clannish",
      sections: ["Incandescence", "Chamomile"]},
      {url: "http://edgeofyourseat.dreamwidth.org/1949.html?style=site",
      title: "he couldn't have imagined",
      sections: ["AAAA-1-Effulgence", "AAAB-2-make a wish"]},
      {url: "http://autokinetic.dreamwidth.org/783.html?style=site",
      title: "(admissions procedures)",
      sections: ["AAAA-1-Effulgence", "AAAB-1-dance between the stars"]},
      {url: "https://glowfic.com/posts/43",
      title: "Book of Discovery",
      sections: ["AAAA-2-Zodiac", "AAAB-1-Book of the Moon"]},
      {url: "https://glowfic.com/posts/50",
      title: "Book of Experience",
      sections: ["AAAA-2-Zodiac", "AAAB-1-Book of the Moon"]},
      {url: "https://glowfic.com/posts/53",
      title: "A fresh start",
      sections: ["AAAA-2-Zodiac", "AAAB-2-Apricum"]},
      {url: "http://alicornutopia.dreamwidth.org/25861.html?style=site",
      title: "Double Witch",
      sections: ["AAAA-4-Bluebell Flames"]},
      {url: "https://alicornutopia.dreamwidth.org/6744.html?thread=2465368&style=site#cmt2465368",
      title: "A Joker summons Demon Cam",
      sections: ["AAAA-3-Demon Cam"],
      title_extras: "(with kappa)"},
      {url: "https://alicornutopia.dreamwidth.org/6744.html?style=site&thread=2560344#cmt2560344",
      title: "Darren summons Demon Cam",
      sections: ["AAAA-3-Demon Cam"],
      title_extras: "(with Aestrix)"}
    ],
    reptest:
    [
      {title: "Shame for us to part",
      url: "https://glowfic.com/posts/519",
      title_extras: "[b][color=#4F012E]tyrians[/color][/b] and [b][color=#960018]carmines[/color][/b] in Sunnyverse",
      report_flags: "4F012E#3F00FF 960018#682860",
      time_new: "2017-01-05T20:51:00"
      },
      {title: "Topology",
      url: "https://glowfic.com/posts/428",
      title_extras: "[b][color=#960018]Rachel[/color][/b] and [b][color=#FF5C5C]Sadde[/color][/b] in the [b][color=#FF5C5C]City of Angles[/color][/b]",
      report_flags: "960018#682860 FF5C5C#FFB25C"
      },
      {title: "The Origin and Misadventures of the Avian Twins",
      url: "https://glowfic.com/posts/489",
      title_extras: "Tabby and Zeke in [b][color=#000000]Rockeye's new world[/color][/b]",
      report_flags: "000000"
      },
    ],
    temp_starlight:
    [
      {url: "https://alicornutopia.dreamwidth.org/29069.html?style=site",
      title: "and in my hands place honesty",
      sections: ["Starlight"]},
      {url: "https://alicornutopia.dreamwidth.org/29401.html?style=site",
      title: "veritable",
      sections: ["Starlight"]}
    ],
    lintamande:
    []
  }

  def self.get_handler_for(thing)
    index_handlers = GlowficIndexHandlers.constants.map {|c| GlowficIndexHandlers.const_get(c) }
    index_handlers.select! {|c| c.is_a?(Class) && c < GlowficIndexHandlers::IndexHandler }
    chapter_handlers = index_handlers.select {|c| c.handles? thing}
    return chapter_handlers.first if chapter_handlers.length == 1
    chapter_handlers
  end

  class IndexHandler
    attr_reader :group
    def initialize(options = {})
      @group = options[:group]
      @chapter_list = options[:chapter_list]
      @old_chapter_list = options[:old_chapter_list]
    end

    def self.handles(*args)
      @handles = args
    end
    def self.handles?(thing)
      return unless @handles
      @handles.include?(thing)
    end
    def handles?(thing)
      self.handles?(thing)
    end

    def chapter_list
      @chapter_list ||= GlowficEpub::Chapters.new
    end

    def persist_chapter_data(params)
      raise(ArgumentException, "params must be a hash") unless params.is_a?(Hash)

      get_detail_params = {only_present: true, chapter_list: @old_chapter_list}
      url = params[:url]
      persists.each do |persist|
        thing = persist[:thing]
        next if !persist[:override] && params[thing].present?
        next if persist[:if] && !params[persist[:if]]
        next if persist[:unless] && params[persist[:unless]]

        get_detail_params[:detail] = thing
        persist_data = get_prev_chapter_detail(group, get_detail_params)
        next unless persist_data.key?(url)

        params[thing] = persist_data[url]
      end

      get_detail_params[:detail] = :"time_new_set?"
      time_new_set = get_prev_chapter_detail(group, get_detail_params)
      if time_new_set[url] && params[:time_new].blank?
        get_detail_params[:detail] = :time_new
        time_news = get_prev_chapter_detail(group, get_detail_params)
        params[:time_new] = time_news[url] if time_news.key?(url)
      end

      params
    end
    def persists
      @persists = [
        #{thing: :param, :if => :param_to_require, :unless => :param_to_avoid, :override => true if delete current params}
        {thing: :pages},
        {thing: :check_pages},
        {thing: :check_page_data},
        {thing: :processed},
        {thing: :entry, :if => :processed},
        {thing: :replies, :if => :processed},
        {thing: :characters, :if => :processed},
        {thing: :entry_title, :if => :processed},
        {thing: :time_completed, :if => :processed},
        {thing: :time_hiatus, :if => :processed},
        {thing: :time_abandoned, :if => :processed},
        {thing: :processed_epub, :if => :processed}
      ]
    end

    def get_chapter_titles(chapter_link, options = {})
      backward = true
      backward = options[:backward] if options.key?(:backward)

      chapter_text = get_text_on_line(chapter_link, stop_at: :a, backward: backward, forward: false).strip
      chapter_text_extras = get_text_on_line(chapter_link, stop_at: :a, backward: false, include_node: false).strip

      if (chapter_text.index('(') && chapter_text_extras.index(')')) || (chapter_text.index('[') && chapter_text_extras.index(']'))
        chapter_text = get_text_on_line(chapter_link, stop_at: :a, backward: backward).strip
        chapter_text_extras = ''
      end # If the title has brackets split between the text & extras, squish it

      if (chapter_text_extras.index('(') == chapter_text_extras.length || chapter_text_extras.index('[') == chapter_text_extras.length)
        chapter_text_extras = chapter_text_extras[0..-2].strip
      end # If it ends in a start-bracket, remove it
      if (chapter_text_extras.index(')') == chapter_text_extras.length && !chapter_text_extras.index('(')) || (chapter_text_extras.index(']') == chapter_text_extras.length && !chapter_text_extras.index('['))
        chapter_text_extras = chapter_text_extras[0..-2].strip
      end # If it ends in an end-bracket, and there's no corresponding start bracket, remove it

      chapter_text_extras = nil if chapter_text_extras.empty?
      [chapter_text, chapter_text_extras]
    end

    def chapter_from_toc(params = {})
      params[:thread] ||= get_url_param(params[:url], 'thread')
      params[:url] = standardize_chapter_url(params[:url])
      params.delete(:thread) unless params[:thread]
      params.delete(:title_extras) if params[:title_extras].nil? || params[:title_extras].empty?

      persist_chapter_data(params)
      return GlowficEpub::Chapter.new(params)
    end
  end

  class CommunityHandler < IndexHandler
    handles :glowfic
    def initialize(options = {})
      super(options)
    end

    def toc_to_chapterlist(options = {})
      fic_toc_url = options[:fic_toc_url]

      defaultCont = :"no continuity"
      chapter_list = {}

      while fic_toc_url.present?
        LOG.info "TOC Page: #{fic_toc_url}"
        fic_toc_data = get_page_data(fic_toc_url, replace: true)
        fic_toc = Nokogiri::HTML(fic_toc_data)

        next_page_link = fic_toc.at_css(".navigation .month-forward a")
        fic_toc_url = nil
        if (next_page_link)
          fic_toc_url = next_page_link.try(:[], :href).try(:strip)
        else
          LOG.info "No next page link"
        end

        entries = fic_toc.css("#archive-month .month .entry-title")
        entries.each do |entry|
          entry_box = entry.parent
          entry_link = entry.at_css('a')

          params = {}
          params[:title] = entry_link.try(:text)
          params[:title_extras] = nil
          params[:url] = entry_link.try(:[], :href)
          next if params[:url].nil? || params[:url].empty?

          params[:url] = standardize_chapter_url(params[:url])

          chapter_tags = entry_box.css("div.tag ul li a")
          skip = false
          complete = false
          chapter_tags.each do |tag_link|
            tag_text = tag_link.text.strip
            if tag_text.downcase.start_with?("continuity:")
              section = tag_text[12..-1].strip.to_sym
              params[:sections] = (section.empty?) ? [defaultCont] : [section]
            end
            if tag_text.downcase.start_with?("meta:")
              skip = true
              break
            end
            if tag_text.downcase.start_with?("status:") && tag_text[": complete"]
              complete = true
            end
          end
          next if skip

          params[:marked_complete] = complete
          params[:sections] ||= [defaultCont]
          chapter_details = chapter_from_toc(params)
          yield chapter_details if block_given?

          chapter_list[params[:sections].first] ||= []
          chapter_list[params[:sections].first] << chapter_details
        end
      end

      continuities = chapter_list.keys.sort
      sorted_chapter_list = self.chapter_list

      continuities.each do |continuity|
        next if (continuity == defaultCont || continuity.downcase == "oneshot")
        chapter_list[continuity].each do |chapter|
          sorted_chapter_list << chapter
        end
      end

      [defaultCont, 'oneshot'].each do |cont|
        if chapter_list.key?(cont)
          chapter_list[cont].each do |chapter|
            sorted_chapter_list << chapter
          end
        end
      end

      sorted_chapter_list
    end
  end

  class OrderedListHandler < IndexHandler
    handles :effulgence, :pixiethreads, :incandescence, :radon, :silmaril
    def initialize(options = {})
      super(options)
      @strip_li_end = (@group == :incandescence || @group == :silmaril)
      @strip_li_end = options[:strip_li_end]
      @silmaril_handling = :constellation
    end

    def get_chapters(section, section_list, index=1, &block)
      #puts "Find chapters in (#{section_list}): #{section.text}"

      chapters = section.css('> ol > li')
      if chapters.present?
        chapters.each_with_index do |chapter, i|
          get_chapters(chapter, section_list, i, &block)
        end
        return
      end

      chapter_link = section.at_css('> a')
      if chapter_link
        if @group == :silmaril && @silmaril_handling == :constellation
          links = section.css('> a')
          chapter_link = links.detect { |link| link[:href]["vast-journey-9935.herokuapp.com/posts/"] || link[:href]["glowfic.com/posts/"] } || chapter_link if links.length > 1
        end
        chapter_links = [chapter_link]
      else
        sublist = section.at_css('> ul')
        return unless sublist.present?
        chapter_links = sublist.css("> li a")
        return unless chapter_links.present?

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

      chapter_links.each do |c_link|
        next if @group == :silmaril && @silmaril_handling != :constellation && c_link.text.strip["constellation import"]

        params = {}
        params[:title] = get_text_on_line(c_link, after: false).strip
        params[:title_extras] = get_text_on_line(c_link, include_node: false, before: false).strip

        params[:title_extras] = params[:title_extras].gsub(/\(?constellation import\)?/, '').strip if @group == :silmaril && @silmaril_handling != :constellation

        open_count = params[:title].scan("(").count - params[:title].scan(")").count
        if open_count > 0 && params[:title_extras].start_with?(")")
          params[:title] += ")"
          params[:title_extras] = params[:title_extras][1..-1]
        end
        params[:url] = c_link.try(:[], :href)
        next unless params[:url]

        params[:sections] = section_list
        chapter_details = chapter_from_toc(params)

        yield chapter_details if block_given?
      end
    end
    def each_section(node, section_list, &block)
      sections = node.css("> ol > li")
      i = 0
      sections.each do |section|
        i = i.next
        sublist = section.at_css('> ol')
        if sublist
          subsection_text = ''
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
    def toc_to_chapterlist(options={})
      fic_toc_url = options[:fic_toc_url]

      LOG.info "TOC Page: #{fic_toc_url}"
      fic_toc_data = get_page_data(fic_toc_url, replace: true)
      fic_toc_data = fic_toc_data.gsub('</li>', '') if @strip_li_end
      fic_toc = Nokogiri::HTML(fic_toc_data)

      entry = fic_toc.at_css('.entry-content')
      return unless entry

      previous_sections = []
      each_section(entry, []) do |section, section_list, section_index|
        get_chapters(section, section_list, section_index) do |chapter_details|
          chapter_list << chapter_details
          sections = chapter_details.sections
          sections.each_with_index do |s, i|
            if previous_sections.length <= i || previous_sections[i] != s
              LOG.info "- Section (depth #{i+1}): #{s}"
            end
          end
          previous_sections = sections
          yield chapter_details if block_given?
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
    def toc_to_chapterlist(options = {})
      fic_toc_url = options[:fic_toc_url]

      LOG.info "TOC Page: #{fic_toc_url}"
      fic_toc_data = get_page_data(fic_toc_url, replace: true)
      fic_toc = Nokogiri::HTML(fic_toc_data)

      entry = fic_toc.at_css('.entry-content')
      return unless entry

      potential_headings = entry.css('b')
      uber_headings = []
      potential_headings.each do |node|
        max_dist = 3
        test_node = node
        is_heading = false
        max_dist.times do
          test_node = test_node.previous
          break unless test_node
          next unless test_node.text?
          is_heading = test_node.text[/\-{3,}/]
        end
        next unless is_heading

        test_node = node
        is_heading = false
        max_dist.times do
          test_node = test_node.next
          break unless test_node
          next unless test_node.text?
          is_heading = test_node.text[/\-{3,}/]
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
        prev_element = top_level.previous
        while prev_element && superheading.nil?
          heading = prev_element if headings.include?(prev_element) && heading.nil?
          superheading = prev_element if uber_headings.include?(prev_element)
          prev_element = prev_element.previous
        end

        in_li = false
        if link.parent.name == "li" && heading.nil?
          parent = link.parent
          in_li = true
          while parent && parent != entry && parent.name != "ol" && parent.name != "ul"
            parent = parent.parent
          end
          if parent && parent != entry
            list = parent
            previous = list.previous
            while previous && previous.name != "i" && previous != superheading
              previous = previous.previous
            end
            if previous && previous != superheading
              heading_text = get_text_on_line(previous).strip
            end
          end
        end

        next if superheading.nil?

        superheading_text = get_text_on_line(superheading).strip
        heading_text = get_text_on_line(heading).strip if heading

        unless superheading_text == prev_superheading
          prev_heading = nil
          prev_superheading = superheading_text
          puts "Superheading: #{superheading_text}"
        end

        if heading_text && heading_text != prev_heading
          prev_heading = heading_text
          puts "Heading: #{heading_text}"
        end

        chapter_text, chapter_text_extras = get_chapter_titles(chapter_link, backward: in_li)

        chapter_url = chapter_link.try(:[], :href)
        next unless chapter_url

        section_list = [superheading_text, heading_text]
        section_list.compact!

        chapter_details = chapter_from_toc(url: chapter_url, title: chapter_text, title_extras: chapter_text_extras, sections: section_list)
        yield chapter_details if block_given?

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
      @heading_selects = ['b, strong', 'u', 'em, i']
      if group == :maggie
        @heading_selects[0] = 'u'
        @heading_selects[1] = 'b, strong'
      elsif group == :throne
        @heading_selects = ['h4', 'h5']
      end
    end
    def get_heading_encapsule(node)
      text = get_text_on_line(node).strip
      node_text = node.text.strip
      return unless text.present? && node_text.present? && text.start_with?(node_text)

      parenter = node
      while parenter && parenter != @entry && parenter.name != "li"
        parenter = parenter.parent
      end
      return unless parenter == @entry

      encapsule = node
      while encapsule && encapsule.parent && encapsule.parent.text == encapsule.text && encapsule.parent != @entry
        encapsule = encapsule.parent
      end
      return encapsule || node
    end
    def toc_to_chapterlist(options = {})
      fic_toc_url = options[:fic_toc_url]

      LOG.info "TOC Page: #{fic_toc_url}"
      fic_toc_data = get_page_data(fic_toc_url, replace: true)
      fic_toc = Nokogiri::HTML(fic_toc_data)

      @entry = fic_toc.at_css(".entry-content")
      return unless entry

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
        unless heading_levels.empty?
          while prev_element && (heading.empty? || heading[0].nil?)
            (heading_levels.length-1).downto(0).each do |i|
              supers_nil = true
              (i).downto(0).each do |y|
                unless heading[y].nil?
                  supers_nil = false
                  break
                end
              end
              heading[i] = prev_element if supers_nil && heading_levels[i].include?(prev_element)
            end
            prev_element = prev_element.previous
          end
        end

        next if (heading.empty? || heading[0].nil?) && !heading_levels.empty?

        heading.each_with_index do |node, i|
          heading_text[i] = get_text_on_line(node).strip if node
        end

        heading_text.each_with_index do |text, i|
          unless text == prev_headings[i]
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
        section_list.compact!

        chapter_details = chapter_from_toc(url: chapter_url, title: chapter_text, title_extras: chapter_text_extras, sections: section_list)
        yield chapter_details if block_given?

        chapter_list << chapter_details
      end

      chapter_list
    end
  end

  class ConstellationIndexHandler < IndexHandler
    handles :constellation, :opalescence, :zodiac, :lighthouse, :rapid_nova
    def initialize(options = {})
      super(options)
    end

    def fix_url_folder(url)
      url.sub(/(users|boards|galleries|characters)\/(\d+)(\?|#|$)/, '\1/\2/\3')
    end
    def get_absolute_url(url_path, current_url)
      if url_path.start_with?('/')
        url_path = "https://glowfic.com" + url_path
      elsif !url_path.start_with?("http://") && !url_path.start_with?("https://")
        url_path = File.join((current_url.split("/")[0..-2]) * '/', url_path)
      end
      url_path = fix_url_folder(url_path)
      url_path
    end

    def board_to_block(options = {})
      board_url = options[:board_url]
      board_url = fix_url_folder(board_url)
      LOG.info "TOC Page: #{board_url}"

      board_toc_data = get_page_data(board_url, replace: true, headers: {"Accept" => "text/html"})
      board_toc = Nokogiri::HTML(board_toc_data)

      content = board_toc.at_css('#content')
      board_sections = content.css('tbody tr th')

      board_title_ele = content.at_css('tr th')
      board_title_ele.at_css('a').try(:remove)
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
          th = chapter_row.at_css('th')
          next if th && !th.try(:[], :colspan)
          chapter_sections = [board_name] if chapter_row.at_css('td.continuity-spacer')
          next if chapter_row[:colspan]
          next if chapter_row.at_css('td').try(:[], :colspan)

          no_post = chapter_row.at_css('.centered.padding-10')
          next if no_post && no_post.text['No posts']

          if th
            section_name = th.at_css('a').try(:text).try(:strip)
            if section_name
              chapter_sections = [board_name, section_name]
            else
              LOG.error "couldn't get section name for th #{th}"
            end
            next
          end

          chapter_link = chapter_row.at_css('td a')
          chapter_title = chapter_link.text.strip
          chapter_url = get_absolute_url(chapter_link['href'], board_url)

          chapter_details = chapter_from_toc(url: chapter_url, title: chapter_title, sections: chapter_sections)

          yield chapter_details if block_given?
        end

        temp_url = previous_url
        previous_url = board_toc.at_css('.pagination a.previous_page').try(:[], :href)
        previous_url = get_absolute_url(previous_url.strip, temp_url) if previous_url
      end
    end

    def userlist_to_block(options = {})
      user_url = options[:user_url]
      user_url = fix_url_folder(user_url)
      LOG.info "TOC Page: #{user_url}"
      user_toc_data = get_page_data(user_url, replace: true, headers: {"Accept" => "text/html"})
      user_toc = Nokogiri::HTML(user_toc_data)

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
        user_posts_header = user_toc.css('th[colspan]').select { |bit| bit.text['Recent Posts'] }

        if user_posts_header.empty?
          LOG.error "No 'recent post' headers for user!"
          return
        elsif user_posts_header.length > 1
          LOG.warn "Many 'recent post' headers!"
        end
        user_body = user_posts_header.first.ancestors('table').first.at_css('tbody')

        chapters = user_body.css('tr')
        chapters = chapters.reverse
        chapters.each do |chapter_row|
          th = chapter_row.at_css('th')
          next if th

          no_post = chapter_row.at_css('.centered.padding-10')
          next if no_post && no_post.text['No posts']

          chapter_link = chapter_row.at_css('td a')
          chapter_title = chapter_link.text.strip
          chapter_url = get_absolute_url(chapter_link[:href], user_url)
          chapter_sections = chapter_row.at_css('.post-board').try(:text).try(:strip)

          next if @group == :lintamande && chapter_sections == 'Silmaril'
          chapter_details = chapter_from_toc(url: chapter_url, title: chapter_title, sections: chapter_sections)
          yield chapter_details if block_given?
        end

        temp_url = previous_url
        previous_url = user_toc.at_css('.pagination a.previous_page').try(:[], :href)
        previous_url = get_absolute_url(previous_url.strip, temp_url) if previous_url
      end
    end

    def toc_to_chapterlist(options = {})
      fic_toc_url = options[:fic_toc_url]
      fic_toc_url = fix_url_folder(fic_toc_url)
      ignore_sections = options[:ignore_sections] || []

      if fic_toc_url.end_with?('/boards/')
        LOG.info "TOC Page: #{fic_toc_url}"
        fic_toc_data = get_page_data(fic_toc_url, replace: true)
        fic_toc = Nokogiri::HTML(fic_toc_data)

        boards = fic_toc.css("#content tr")
        boards.each do |board|
          next if board.at_css("th")

          board_link = board.at_css('a')
          board_name = board_link.text.strip
          next if ['Site testing', 'Effulgence', 'Witchlight', 'Lighthouse', 'Opalescence', 'Silmaril', 'Zodiac', 'Rapid Nova'].include?(board_name)
          next if ignore_sections.include?(board_name)
          board_url = get_absolute_url(board_link["href"], fic_toc_url)

          board_to_block(board_url: board_url) do |chapter_details|
            chapter_list << chapter_details
            yield chapter_details if block_given?
          end
        end
      elsif fic_toc_url[/\/boards\/\d+/]
        board_to_block(board_url: fic_toc_url) do |chapter_details|
          chapter_list << chapter_details
          yield chapter_details if block_given?
        end
      elsif fic_toc_url[/\/users\/\d+/]
        chapter_list.sort_chapters = true
        chapter_list.get_sections = true
        userlist_to_block(user_url: fic_toc_url) do |chapter_details|
          if chapter_details.sections.present?
            board_name =
              if chapter_details.sections.is_a?(Array)
                chapter_details.sections.first
              else
                chapter_details.sections
              end
            next if ignore_sections.include?(board_name)
          end

          chapter_details.sections = nil # Clear sections so it'll get the sections in the handlers_sites thing.
          chapter_list << chapter_details
          yield chapter_details if block_given?
        end
      else
        raise(ArgumentException, "URL is not an accepted format – failed")
      end
      chapter_list
    end
  end

  class TestIndexHandler < IndexHandler
    handles :test, :temp_starlight, :lintamande, :report, :mwf_leaf, :mwf_lioncourt, :reptest
    def initialize(options = {})
      super(options)
    end
    def toc_to_chapterlist(options = {})
      list = INDEX_PRESETS[@group]

      if @group == :test
        chapter_list.sort_chapters = true
        chapter_list.get_sections = true
      elsif @group == :report
        chapter_list.sort_chapters = true
        chapter_list.get_sections = true
        @group_folder = "web_cache/#{@group}"
        url = REPORT_LIST_URL
        file_path = get_page_location(url, where: @group_folder)
        if File.file?(file_path)
          open(file_path) do |old|
            text = old.read
            break if text.strip.length <= 10
            open(file_path + '.bak', 'w') { |newf| newf.write text }
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
        fic_toc_url = options[:fic_toc_url]

        LOG.info "TOC Page: #{fic_toc_url}"
        fic_toc_data = get_page_data(fic_toc_url, replace: true)
        fic_toc = Nokogiri::HTML(fic_toc_data)

        list = []
        msg = fic_toc.at_css('.post.first').try(:at_css, '.message')
        if msg
          if @group == :mwf_leaf
            msg.css('> ul > li').each do |li|
              sections = nil
              elems =
                if li.at_css('ul')
                  sections = ["Lioncourt's coronation party"]
                  li.css('ul li a')
                elsif li.at_css('a')
                  li.at_css('a')
                end

              elems.each do |li_a|
                url = li_a[:href]
                if url["redirect.viglink.com"]
                  url = url.split('&u=').last.gsub('%3A', ':').gsub('%3F', '?').gsub('%3D', '=').gsub('%26', '&')
                end
                name = li_a.text.strip

                param_hash = {url: url, title: name}
                param_hash[:sections] = sections if sections
                list << param_hash
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
              neater_url = url.sub('http://', 'https://').sub(/[&\?]style=site/, '').sub(/[&\?]view=flat/, '')
              if prev_url.present? and neater_url.start_with?(prev_url)
                puts "Skipping #{name} because thread of previous"
              elsif neater_url.start_with?('http')
                prev_url = neater_url
                list << {url: url, title: name}
              end
            end
          end
        end
      elsif @group == :lintamande
        const_handler = ConstellationIndexHandler.new(group: @group)
        chapter_list.sort_chapters = true
        chapter_list.get_sections = true
        const_chapters = const_handler.toc_to_chapterlist(fic_toc_url: FIC_TOCS[@group], ignore_sections: ['Silmaril']) do |chapter|
          yield chapter if block_given?
        end
        const_chapters.each do |chapter|
          chapter_list << chapter
        end
      end

      list.each do |item|
        chapter_details = chapter_from_toc(item)
        yield chapter_details if block_given?
        chapter_list << chapter_details
      end

      return chapter_list
    end
  end

  ##
  # class HandlerTemplate < IndexHandler
  #   def initialize(options = {})
  #     super(options)
  #   end
  #
  #   # chapter_list is initialized when used
  #
  #   def toc_to_chapterlist(options = {}, &block)
  #     fic_toc_url = options[:fic_toc_url]
  #
  #     LOG.info "TOC Page: #{fic_toc_url}"
  #     fic_toc_data = get_page_data(fic_toc_url, replace: true)
  #     fic_toc = Nokogiri::HTML(fic_toc_data)
  #
  #     ### Gather information from the page to generate appropriate chapter details
  #     ### e.g.
  #     entry = fic_toc.at_css('.entry-content')
  #     return unless entry
  #
  #     chapter_link = entry.at_css('a')
  #     chapter_url = chapter_link.try(:[], :href)
  #     chapter_title = get_text_on_line(chapter_link).strip
  #     return unless chapter_url
  #
  #     section_list = ["no section"]
  #
  #     chapter_details = chapter_from_toc(url: chapter_url, title: chapter_title, sections: section_list)
  #
  #     yield chapter_details if block_given?
  #
  #     chapter_list << chapter_details
  #     chapter_list
  #   end
  # end
end
