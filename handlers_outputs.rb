module GlowficOutputHandlers
  require 'scraper_utils'
  require 'models'
  require 'uri'
  require 'erb'
  include ScraperUtils
  include GlowficEpub::PostType

  class OutputHandler
    include GlowficEpub
    include ScraperUtils
    def initialize(options={})
      @chapters = options[:chapters] if options.key?(:chapters)
      @chapters = options[:chapter_list] if options.key?(:chapter_list)
      @chapters.sort_chapters! if @chapters.is_a?(GlowficEpub::Chapters) && @chapters.sort_chapters
      @group = options[:group] if options.key?(:group)
    end
  end

  class EpubHandler < OutputHandler
    include ERB::Util

    def initialize(options={})
      super options
      require 'eeepub'

      @skipnavmodes = [:epub, :epub_nosplit]

      @mode = options.fetch(:mode, :epub)
      @no_split = options.fetch(:no_split, false)
      @mode = (@mode.to_s + '_nosplit').to_sym if @no_split
      @folder_name = @group.to_s

      @mode_folder = File.join('output', @mode.to_s)
      @group_folder = File.join(@mode_folder, @folder_name)
      @style_folder = File.join(@group_folder, 'style')
      @html_folder = File.join(@group_folder, 'html')
      @images_folder = File.join(@group_folder, 'images')
      FileUtils::mkdir_p @style_folder
      FileUtils::mkdir_p @html_folder
      FileUtils::mkdir_p @images_folder

      @replies_per_split = options.fetch(:replies_per_split, 200)
      @replies_per_split = 99999 if @no_split
      @min_replies_in_split = options.fetch(:min_replies_in_split, 50)

      @face_path_cache = {}
      @paths_used = []
      @cachedimgs_added = []
    end

    def add_cachedimg_path(face_path)
      return true if @cachedimgs_added.include?(face_path)
      (LOG.error "face_path doesn't start with '../' – is probably not local"; return) unless face_path.start_with?('../')
      relative_file = face_path.sub('../', '')
      @files << {File.join(@group_folder, relative_file) => File.join('EPUB', File.dirname(relative_file))}
      @cachedimgs_added << face_path
      true
    end
    def get_face_path(face)
      face_url = face if face.is_a?(String)
      face_url = face.imageURL if face.is_a?(Face)
      return '' if face_url.blank?
      return @face_path_cache[face_url] if @face_path_cache.key?(face_url)
      LOG.debug "get_face_path('#{face_url}')"

      face_url = face_url.gsub(' ', '%20').gsub('!', '%21').gsub('$', '%24').gsub("'", '%27').gsub('(', '%28').gsub(')', '%29').gsub('*', '%2A').gsub(',', '%2C').gsub('[', '%5B').gsub(']', '%5D')
      face.imageURL = face_url if face.is_a?(Face) && face.imageURL != face_url

      uri = URI.parse(face_url)
      save_path = @group_folder
      uri_path = uri.path
      uri_path = uri_path[1..-1] if uri_path.start_with?('/')
      filename = URI.unescape(uri_path.gsub('/', '-'))
      if filename.length > 100
        temp_extension = filename.split('.').last
        temp_filename = filename.sub(".#{temp_extension}", '')
        temp_filename = temp_filename[0..50]
        temp_filename += '.' + temp_extension if temp_extension.length < 20 and temp_extension != filename
        LOG.debug "Shortening filename from #{filename} to #{temp_filename}"
        filename = temp_filename
      end

      test_ext = filename.split('.').last
      test_ext = "png" if test_ext == filename
      test_ext = "." + test_ext if test_ext.present?
      test_filename = 'img-' + filename.sub("#{test_ext}", "").gsub(/[^a-zA-Z0-9_\-]+/, "_")
      i = 0
      relative_file = sanitize_local_path(File.join('images', uri.host, test_filename + test_ext))
      while @paths_used.include?(relative_file)
        i += 1
        temp_filename = "#{test_filename}_#{i}"
        relative_file = sanitize_local_path(File.join('images', uri.host, temp_filename + test_ext))
        LOG.debug "There was an issue with the previous file. Trying alternate path: #{temp_filename + test_ext}"
      end
      try_down = get_page(face_url, save_path: File.join(save_path, relative_file), replace: false)
      unless try_down
        @face_path_cache[face_url] = "" # So it doesn't error multiple times for a single icon
        return ""
      end
      @paths_used << relative_file

      @files << {File.join(save_path, relative_file) => File.join('EPUB', File.dirname(relative_file))}
      @face_path_cache[face_url] = File.join("..", relative_file)
    end
    def get_comment_path(comment_url)
      return comment_url unless comment_url.start_with?('http://') || comment_url.start_with?('https://')
      return comment_url unless comment_url['.dreamwidth.org/'] || comment_url['vast-journey-9935.herokuapp.com/'] || comment_url['glowfic.com/']
      comment_url = comment_url.gsub('&amp;', '&')
      comment_uri = URI.parse(comment_url)
      fragment = comment_uri.fragment

      site = nil
      post_id = nil
      if comment_uri.host['.dreamwidth.org/']
        comment_id = /(comment|cmt)-?(\d+)/.match(fragment).try(:[], 2) ||  get_url_param(comment_uri, 'thread')
        comment_id = 'cmt' + comment_id if comment_id
        post_id = /\/(\d+)(.html)?$/.match(comment_uri.path).try(:[], 1)
        site = :dreamwidth
      elsif comment_uri.host['vast-journey-9935.herokuapp.com/'] || comment_uri.host['glowfic.com/']
        comment_id = /reply-(\d+)/.match(fragment).try(:[], 1) || /\/replies\/(\d+)/.match(comment_uri.path).try(:[], 1)
        post_id = /posts\/(\d+)/.match(comment_uri.path).try(:[], 1)
        site = :constellation
      else
        LOG.error "chapter was not from dreamwidth or constellation? #{comment_url}"
        return comment_url
      end

      comment_path = nil
      @chapters.each do |chapter|
        next if chapter.thread.present? && comment_id.blank? # skip if pointing to a post and chapter is a specific thread
        next if chapter.shortURL.start_with?('constellation') && site != :constellation
        next if !chapter.shortURL.start_with?('constellation') && site == :constellation
        next if post_id && !chapter.shortURL.split('/').include?(post_id)
        if comment_id
          reply = chapter.replies.detect { |i| i.id.to_s == comment_id }
          next unless reply
          page = get_message_page(reply)
          comment_path = get_chapter_path_bit(chapter: chapter, page: page) + "#comment-#{reply.id}"
        else
          comment_path = get_chapter_path_bit(chapter: chapter)
        end
        break if comment_path
      end
      comment_path || comment_url
    end

    def get_chapter_path(options = {})
      File.join(@html_folder, get_chapter_path_bit(options))
    end
    def get_relative_chapter_path(options = {})
      File.join('EPUB', 'html', get_chapter_path_bit(options))
    end
    def get_chapter_path_bit(options = {})
      chapter = options if options.is_a?(Chapter)
      chapter ||= options[:chapter] if options.is_a?(Hash)

      chapter_url = chapter.try(:url)
      chapter_url ||= options if options.is_a?(String)
      chapter_url ||= options[:chapter_url] if options.is_a?(Hash)

      thread = get_url_param(chapter_url, 'thread')

      page = options[:split] || options[:page] if options.is_a?(Hash)
      page ||= 1 # 1-based pagination.

      uri = URI.parse(chapter_url)
      save_file = uri.host.sub('.dreamwidth.org', '').sub('vast-journey-9935.herokuapp.com', 'constellation').sub('www.glowfic.com', 'constellation').sub('glowfic.com', 'constellation')
      uri_path = uri.path
      uri_path = uri_path[1..-1] if uri_path.start_with?('/')
      save_file += '-' + uri_path.sub('.html', '')
      save_file += "-#{thread}" if thread.present?
      save_file += '-split%03d' if page > 1
      save_file.gsub('/', '-') + '.html' # save_path
    end

    def navify_navbits(navbits)
      navified = []
      if navbits.key?(:_order)
        navbits[:_order].each do |section_name|
          thing = {label: section_name}
          thing[:nav] = navify_navbits(navbits[section_name])
          navified << thing
        end
      end
      if navbits.key?(:_contents)
        navbits[:_contents].each do |thing|
          thing[:content] = get_relative_chapter_path(chapter: thing.delete(:chapter)) if thing.key?(:chapter)
          navified << thing
        end
      end
      navified
    end

    def html_from_navarray(navbits)
      if navbits.is_a?(Array)
        html = "<ol>\n"
        navbits.each do |navbit|
          html << html_from_navarray(navbit)
        end
        html << "</ol>\n"
        html = "" if html == "<ol>\n</ol>\n"
      else
        html = "<li>"
        if navbits.key?(:nav)
          html << h(navbits[:label]) + "\n"
          html << html_from_navarray(navbits[:nav])
        else
          html << "<a href='" << navbits[:content].sub(/^EPUB(\/|\\)/, '') << "'>#{h(navbits[:label])}</a>"
        end
        html << "</li>\n"
        html = "" if html == "<li></li>\n" || html == "<li>\n</li>\n"
      end
      html
    end

    def get_message_orders(chapter)
      # Orders the messages for the chapter (0 is 0th, 1 is next, etc)
      # Value of -1 means entry, else it's position in chapter.replies
      @message_orders ||= {}
      chapter_pathbit = get_chapter_path_bit(chapter)
      return @message_orders[chapter_pathbit] if @message_orders.key?(chapter_pathbit)

      chapter_order = []
      message = chapter.entry
      while message
        message_num = (message == chapter.entry) ? -1 : chapter.replies.index(message)
        chapter_order << message_num unless chapter_order.include?(message_num)

        new_msg = message.children.detect do |child|
          !chapter_order.include?(chapter.replies.index(child))
        end
        new_msg ||= message.parent

        message = new_msg
      end

      warned = false
      chapter.replies.each do |reply|
        message_num = chapter.replies.index(reply)
        next if chapter_order.include?(message_num)
        chapter_order << message_num
        next if warned
        LOG.error "Chapter #{chapter} didn't get all messages via depth traversal."
        warned = true
      end

      @message_orders[chapter_pathbit] = chapter_order
      chapter_order
    end
    def get_message_page(message)
      orders = get_message_orders(message.chapter)
      val = (message == message.chapter.entry) ? -1 : message.chapter.replies.index(message)
      orderval = orders.index(val) + 1 # => entry is '1'
      get_page_from_order_and_total(orderval, orders.length)
    end
    def get_page_from_order_and_total(order, total) # 1-based order
      return 1 if order <= @replies_per_split
      temp = (order / @replies_per_split.to_f).ceil # gives 2 for 399 and 400, gives 3 for 599 and 600 (1…200, 201…400, etc.)
      return temp if order <= (total / @replies_per_split.to_f).floor * @replies_per_split # between 201 and lowest multiple of 200 less than max

      # in last page
      if total % @replies_per_split < @min_replies_in_split
        # if we squish the last page, reduce the num:
        temp = temp - 1
      end
      temp
    end

    def output(chapter_list=nil)
      chapter_list ||= @chapters
      (LOG.fatal "No chapters given!"; return) unless chapter_list

      template_message = open('template_message.erb') { |file| file.read }

      style_path = File.join(@style_folder, 'default.css')
      open('style.css', 'r') do |style|
        open(style_path, 'w') do |css|
          css.write style.read
        end
      end

      # local_file => epub_folder
      @files = [{style_path => 'EPUB/style'}]

      @show_authors = FIC_SHOW_AUTHORS.include?(@group)
      @changed = false

      @save_paths_used = []
      @rel_paths_used = []
      chapter_count = chapter_list.count
      chapter_list.each_with_index do |chapter, i|
        @chapter = chapter
        (LOG.error "(#{i+1}/#{chapter_count}) #{chapter}: No entry for chapter."; next) unless chapter.entry
        (LOG.info "#{chapter}: Chapter is entry-only.") if chapter.replies.blank?
        save_path = get_chapter_path(chapter: chapter, group: @group)
        (LOG.info "(#{i+1}/#{chapter_count}) #{chapter}: Duplicate chapter not added again"; next) if @save_paths_used.include?(save_path)
        rel_path = get_relative_chapter_path(chapter: chapter)

        @save_paths_used << save_path
        @rel_paths_used << rel_path

        if chapter.processed_output?(@mode)
          message_count = chapter.replies.count + 1
          splits = get_page_from_order_and_total(message_count, message_count)
          1.upto(splits) do |page_num|
            temp_path = get_chapter_path(chapter: chapter, group: @group, page: page_num)
            chapter.processed_output_delete(@mode) unless File.file?(temp_path)
          end

          if chapter.processed_output?(@mode)
            1.upto(splits) do |page_num|
              split_save_path = get_chapter_path(chapter: chapter, group: @group, page: page_num)
              split_rel_path = get_relative_chapter_path(chapter: chapter, page: page_num)
              @files << {split_save_path => File.dirname(split_rel_path)}
              open(split_save_path, 'r') do |file|
                noko = Nokogiri::HTML(file.read)
                noko.css('img').each do |img|
                  next unless img.try(:[], :src)
                  add_cachedimg_path(img[:src])
                end
              end
            end

            LOG.info "(#{i+1}/#{chapter_count}) #{chapter}: cached data used."
            next
          end
          LOG.error "#{chapter}: cached data was not found."
        end


        @messages = get_message_orders(chapter).map { |count| (count >= 0) ? chapter.replies[count] : chapter.entry }

        erb = ERB.new(template_message, 0, '-')
        @message_htmls = @messages.map do |message|
          @message = message
          b = binding
          erb.result b
        end

        @split_htmls = []

        html_start = "<!doctype html>\n<html>\n<head><meta charset=\"UTF-8\" /><link rel=\"stylesheet\" href=\"../style/default.css\" type=\"text/css\" /></head>\n<body>\n"
        html_end = "</body>\n</html>\n"

        temp_html = ''
        prev_page = 0
        done_headers = false
        page_count = get_message_page(@messages.last)
        @message_htmls.each_with_index do |message_html, y|
          message = @messages[y]
          page = get_message_page(message)
          unless prev_page == page
            if temp_html.present? && temp_html != html_start
              temp_html += "<a class='navlink nextlink splitlink' href='#{get_chapter_path_bit(chapter: chapter, page: prev_page+1)}'>Next page of chapter &raquo;</a>\n" if !@skipnavmodes.include?(@mode) && prev_page < page_count
              temp_html << html_end
              @split_htmls << temp_html
            end

            # New HTML:
            temp_html = html_start
            temp_html += "<a class='navlink prevlink splitlink' href='#{get_chapter_path_bit(chapter: chapter, page: page-1)}'>&laquo; Previous page of chapter</a>\n" if !@skipnavmodes.include?(@mode) && page > 1
            prev_page = page
          end

          unless done_headers
            temp_html += "<div class=\"chapter-header\">\n"
            temp_html << "<h2 class=\"section-title\">#{h(chapter.sections * ', ')}</h2>\n" if chapter.sections.present?
            temp_html << "<h3 class=\"entry-title\">#{h(chapter.title)}</h3>\n"
            temp_html << "<strong class=\"entry-subtitle\">#{h(chapter.title_extras)}</strong><br />\n" if chapter.title_extras
            temp_html << "<strong class=\"entry-authors\">Authors: #{h(chapter.moieties * ', ')}</strong><br />\n" if @show_authors && @chapter.moieties.present?
            temp_html << "</div>\n"
            done_headers = true
          end

          parent = message.parent
          if parent && parent.children && parent.children.length > 1
            child_index = parent.children.index(message)
            if child_index == 0
              temp_html += "<div class=\"branchnote branchnote1\">This is a branching point! Branch 1:</div>"
            else
              temp_html += "<div class=\"branchnote branchnote#{child_index+1}\">The previous branch has ended. Branch #{child_index+1}:</div>"
            end
          end
          temp_html += message_html << "\n"
        end

        if temp_html.present? && temp_html != html_start
          temp_html << html_end
          @split_htmls << temp_html
        end

        @split_htmls.each_with_index do |page_data, y|
          page = Nokogiri::HTML(page_data)
          page.css('img').each do |img_element|
            img_src = img_element.try(:[], :src)
            next unless img_src
            next unless img_src.start_with?('http://') || img_src.start_with?('https://')
            img_element[:src] = get_face_path(img_src)
          end
          page.css('a').each do |a_element|
            a_href = a_element.try(:[], :href)
            next unless a_href
            a_href = "https://glowfic.com" + a_href if a_href[/^\/(replies|posts|galleries|characters|users|templates|icons)\//]
            a_element[:href] = get_comment_path(a_href)
          end

          split_save_path = get_chapter_path(chapter: chapter, group: @group, page: y+1)
          split_rel_path = get_relative_chapter_path(chapter: chapter, page: y+1)

          open(split_save_path, 'w') do |file|
            file.write page.to_xhtml(indent_text: '', encoding: 'UTF-8')
          end
          @files << {split_save_path => File.dirname(split_rel_path)}
        end

        chapter.processed_output_add(@mode) unless chapter.processed_output?(@mode)
        @changed = true
        LOG.info "(#{i+1}/#{chapter_count}) Did chapter #{chapter}" + (@split_htmls.length > 1 ? " (#{@split_htmls.length} splits)" : '')
      end

      nav_array = []
      contents_allowed = @rel_paths_used
      chapter_list.each do |chapter|
        if contents_allowed.present? && !contents_allowed.include?(get_relative_chapter_path(chapter: chapter))
          LOG.info "Ignoring chapter in NAV: #{chapter}. Not in contents_allowed."
          next
        end

        section_bit = nav_array
        chapter.sections.each do |section|
          section_nav = section_bit
          if section_nav.is_a?(Hash)
            section_nav[:nav] ||= []
            section_nav = section_nav[:nav]
          end

          subsection_bit = section_nav.detect{|sub_bit| sub_bit[:label] == section}
          unless subsection_bit
            subsection_bit = {label: section, content: get_relative_chapter_path(chapter)}
            section_nav << subsection_bit
          end
          section_bit = subsection_bit
        end

        section_array = section_bit
        if section_bit.is_a?(Hash)
          section_bit[:nav] ||= []
          section_array = section_bit[:nav]
        end
        section_array << {label: chapter.title, content: get_relative_chapter_path(chapter)}
      end

      open(File.join(@group_folder, 'toc.html'), 'w') do |toc|
        toc.write html_from_navarray(nav_array)
      end

      @files.each do |thing|
        thing.keys.each do |key|
          next if key.start_with?('/')
          thing[File.join(Dir.pwd, key)] = thing.delete(key)
        end
      end

      if @mode == :epub || @mode == :epub_nosplit
        group_name = @group
        uri = URI.parse(FIC_TOCS[group_name])
        uri_host = uri.host
        uri_host = '' unless uri_host
        files_list = @files
        epub_path = File.join(@mode_folder, "#{@folder_name}.epub")
        epub = EeePub.make do
          title FIC_NAMESTRINGS[group_name]
          creator FIC_AUTHORSTRINGS[group_name]
          publisher uri_host
          date DateTime.now.strftime('%Y-%m-%d')
          identifier FIC_TOCS[group_name], scheme: 'URL'
          uid "glowfic-#{group_name}" + (@no_split ? '-nosplit' : '')

          files files_list
          nav nav_array
        end
        epub.save(epub_path)
      end
      @changed
    end
  end

  class ReportHandler < OutputHandler
    def initialize(options={})
      super options
      @flag_scan = Regexp.new(/ (\(\[color=#([A-F0-9]+)\]███\[\/color\]\)|\(\[color=#([A-F0-9]+)\]██\[\/color\]\[color=#([A-F0-9]+)\]█\[\/color\]\))/)
      @col_scan = Regexp.new(/((^|(?<= ))#?[A-F0-9]{3}[A-F0-9]{3}?(#[A-F0-9]{3}[A-F0-9]{3}?)*($|(?= )))/)
      @flag_pri_scan = Regexp.new(/\[color=#([A-F0-9]+)\](██|███)\[\/color\]/)
      @flag_sec_scan = Regexp.new(/\[color=#([A-F0-9]+)\](█|███)\[\/color\]/)
      @hex = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F']
    end

    def rainbow_comp(thing1, thing2)
      @thing1_pri = thing1.match(@flag_pri_scan).try(:[], 1) || thing1
      @thing1_sec = thing1.match(@flag_sec_scan).try(:[], 1) || thing1
      @thing2_pri = thing2.match(@flag_pri_scan).try(:[], 1) || thing2
      @thing2_sec = thing2.match(@flag_sec_scan).try(:[], 1) || thing2

      #puts "#{thing1} #{thing2}"
      #puts "#{@thing1_pri} #{@thing1_sec} #{@thing2_pri} #{@thing2_sec}"

      @thing1_pri = csscol_to_rgb(@thing1_pri)
      @thing1_sec = csscol_to_rgb(@thing1_sec)
      @thing2_pri = csscol_to_rgb(@thing2_pri)
      @thing2_sec = csscol_to_rgb(@thing2_sec)
      #puts "#{@thing1_pri} #{@thing1_sec} #{@thing2_pri} #{@thing2_sec}"
      #puts "#{rgb_to_hsl(@thing1_pri)} #{rgb_to_hsl(@thing2_pri)}"

      comp = hsl_comp(rgb_to_hsl(@thing1_pri), rgb_to_hsl(@thing2_pri))
      if comp == 0
        comp = hsl_comp(rgb_to_hsl(@thing1_sec), rgb_to_hsl(@thing2_sec))
      end
      #puts "Compared #{thing1} and #{thing2} and got #{comp}"
      comp
    end

    def chapterthing_displaytext(chapterthing, options = {})
      first_last = if options.key?(:first)
        options[:first] != false ? :first : :last
      elsif options.key?(:last)
        options[:last] != false ? :last : :first
      elsif options.key?(:first_last)
        options[:first_last]
      else
        :first
      end
      show_completed_before = options[:completed] || options[:completed_before] || (DateTime.new(@date.year, @date.month, @date.day, 10, 0, 0) - 1)
      show_completed_before ||= 0
      show_hiatus_before = show_completed_before
      show_new_after = options[:early] || options[:new_after] || (DateTime.new(@date.year, @date.month, @date.day, 10, 0, 0) - 1)
      show_last_update_time = options[:show_last_update_time]
      show_sections = options[:show_sections]
      show_last_author = options[:show_last_author]
      show_unread_link = options[:show_unread_link]

      chapter = chapterthing[:chapter]
      first_update = chapterthing[:first_update]
      last_update = chapterthing[:last_update]
      latest_update = chapterthing[:latest_update]
      completed = (chapter.time_completed && chapter.time_completed <= show_completed_before)
      hiatus = (chapter.time_hiatus && chapter.time_hiatus <= show_hiatus_before)
      url_thing = if first_last == :first
        first_update
      elsif first_last == :last
        last_update
      else
        latest_update
      end
      @errors << "#{chapter} has no url_thing! (first_last: #{first_last})" unless url_thing

      show_last_author = !completed if show_last_author == :unless_completed

      if chapter.report_flags && !chapter.report_flags_processed?
        flag_matches = chapter.report_flags.scan(@col_scan).map {|thing| thing[0]}.uniq
        flag_strings = flag_matches.map do |thing|
          thing = thing[1..-1] if thing.start_with?('#')
          things = thing.split('#')
          if things.length == 1
            "[color=##{things.first}]███[/color]"
          elsif things.length == 2
            "[color=##{things.first}]██[/color][color=##{things.last}]█[/color]"
          else
            temp = ''
            things.each {|col| temp << "[color=##{col}]█[/color]"}
            temp
          end
        end
        chapter.report_flags = flag_strings.sort{|thing1, thing2| rainbow_comp(thing1, thing2) }.join(' ').tr('()', '').strip
        chapter.report_flags_processed = true
      end

      if chapter.title_extras.present? && !chapter.report_flags.present?
        flag_matches = chapter.title_extras.scan(@flag_scan).map{|thing| thing[0] }.uniq
        chapter.report_flags = flag_matches.sort{|thing1, thing2| rainbow_comp(thing1, thing2) }.join(' ').tr('()', '').strip
        chapter.title_extras = chapter.title_extras.gsub(@flag_scan, '')
      end

      chapter.report_flags ||= ''
      show_last_author = false unless latest_update.author_str

      @errors << "#{chapter}: both completed and hiatused" if completed && hiatus

      section_string = ''
      if show_sections && chapter.sections.present?
        str = chapter.sections * ' > '
        @cont_replace.each {|key, val| str = str.sub(key, val)}
        section_string = '(' + str + ') '
      end

      str = "[*]"
      str << '[size=85]' + chapter.report_flags.strip + '[/size] ' unless chapter.report_flags.blank?
      if chapter.time_new >= show_new_after
        str << '([b]New[/b]) '
      elsif chapter.fauxID['constellation'] && show_unread_link
        str << "([url=#{set_url_params(clear_url_params(chapter.url), {page: 'unread'})}#unread]→[/url]) "
      end
      str << section_string
      str << "[url=#{url_thing.permalink}]" if url_thing
      str << '[color=#9A534D]' if hiatus
      str << '[color=goldenrod]' if completed
      str << "#{chapter.entry_title}"
      str << '[/color]' if completed
      str << '[/color]' if hiatus
      str << '[/url]' if url_thing
      str << ',' unless chapter.entry_title && chapter.entry_title[/[?,.!;…\-–—]$/] #ends with punctuation (therefore 'don't add a comma')
      str << ' '
      str << "#{chapter.title_extras || '(no extras)'}"
      str << ' (' if show_last_author || show_last_update_time
      str << "last post by #{latest_update.author_str}" if show_last_author
      str << ', ' if show_last_author && show_last_update_time
      str << 'last updated ' + latest_update.time.strftime((latest_update.time.year != @date.year ? '%Y-' : '') + '%m-%d %H:%M') if show_last_update_time
      str << ')' if show_last_author || show_last_update_time
      return str
    end
    def sort_by_time(upd_chapters, value)
      upd_chapters.sort! do |x,y|
        time_y = y[:chapter].time_new if y[value] == y[:chapter].entry
        time_x = x[:chapter].time_new if x[value] == x[:chapter].entry
        time_y = y[value].time
        time_x = x[value].time
        order = time_y <=> time_x
        next order unless order == 0
        if y[:chapter].fauxID['constellation'] && x[:chapter].fauxID['constellation']
          y[value].id <=> x[value].id # have higher IDs first, will be more recently updated
        else
          y[:chapter].fauxID <=> x[:chapter].fauxID # if not constellation, sort by chapter ID
        end
      end
    end
    def report_output(thing)
      @report_output ||= ''
      @report_output += thing + "\n"
    end
    def report_output!
      LOG.info @report_output.strip
    end
    def report_list(chapters, options={})
      spoiler_box = options.delete(:spoiler_box)
      list_style = options.delete(:list_style)
      message = options.delete(:message)

      report_output "[spoiler-box=#{spoiler_box}]" if spoiler_box
      report_output message
      report_output "[list#{list_style ? '=' + list_style : ''}]"
      chapters.each do |chapter_thing|
        report_output chapterthing_displaytext(chapter_thing, options)
      end
      report_output "[/list]"
      report_output "[/spoiler-box]" if spoiler_box
    end

    def output(options = {})
      chapter_list = options.fetch(:chapter_list, @chapters)
      show_earlier = options[:show_earlier]
      @cont_replace = options.fetch(:cont_replace, {/^ZZ+\d+-/ => ''})
      date = options.fetch(:date, DateTime.now.to_date)
      @date = date
      (LOG.fatal "No chapters given!"; return) unless chapter_list
      @errors = []

      today_time = DateTime.new(@date.year, @date.month, @date.day, 10, 0, 0)

      chaptercount = chapter_list.length
      LOG.progress("Organizing chapters for report", 0, chaptercount)
      done = []
      upd_chapter_col = {} # save each "upd_chapters", indexed by days_ago
      day_list = [1,2,3,4,5,6,7,-1]
      day_list.each do |days_ago|
        early_time = today_time - days_ago
        late_time = early_time + 1

        # special case the "Today, Not Yesterday"
        if days_ago == 2
          upd_chapter_col[1].each do |chapter_thing|
            chapter = chapter_thing[:chapter]

            # check if entry/time_new was yesterday
            was_yesterday = chapter.time_new.between?(early_time, late_time)

            # if time_new is >= yesterday, skip the next check
            # (i.e. if time_new is yesterday, it updated yesterday; else it was not)
            # (also used for when time_new is manually set)
            if chapter.time_new > early_time
              chapter_thing[:yesterday] = was_yesterday
              next
            end

            # check each reply to see if chapter was updated yesterday
            chapter.replies.reverse_each do |message|
              break if was_yesterday
              next unless message.time.between?(early_time, late_time)
              was_yesterday = true
            end

            chapter_thing[:yesterday] = was_yesterday
          end
        end

        upd_chapters = []
        chapter_list.each do |chapter|
          next if done.include?(chapter)
          next unless chapter.entry
          if chapter.time_new >= today_time
            # skip if it's later than today
            @errors << "Updated more recently than specified day: #{chapter}"
            done << chapter
            LOG.progress("Organizing chapters for report", done.length, chaptercount)
            next
          end

          first_update = nil
          last_update = nil
          latest_update = nil
          if days_ago > 0 && chapter.time_new.between?(early_time, late_time)
            first_update = chapter.entry
            last_update = chapter.entry
            latest_update = chapter.entry
          end

          messages = chapter.replies
          # messages are probably in chronological order (oldest first); ignore cases where this is not true
          messages.each do |message|
            latest_update = message if message.time < today_time
            next unless days_ago > 0 # skip "earlier" extra checks
            next unless message.time.between?(early_time, late_time) # only apply to relevant messages
            first_update = message unless first_update
            last_update = message
          end

          if first_update
            upd_chapters << {chapter: chapter, first_update: first_update, last_update: last_update, latest_update: latest_update}
            done << chapter
            LOG.progress("Organizing chapters for report", done.length, chaptercount)
          elsif days_ago < 1
            upd_chapters << {chapter: chapter, latest_update: latest_update}
            done << chapter
            LOG.progress("Organizing chapters for report", done.length, chaptercount)
          end
        end

        upd_chapter_col[days_ago] = upd_chapters
      end
      LOG.progress("Organized chapters for report.\n" + '-' * 60)

      day_list.each do |days_ago|
        early_time = today_time - days_ago
        late_time = early_time + 1

        upd_chapters = upd_chapter_col[days_ago]
        next if upd_chapters.empty?

        # Do the optional "Earlier:" section (at the end)
        if show_earlier && days_ago < 1
          sort_by_time(upd_chapters, :latest_update)
          if upd_chapters.present?
            report_list(upd_chapters, first_last: :latest, completed_before: late_time, new_after: today_time + 3, show_last_update_time: true, show_last_author: :unless_completed, message: 'Earlier:')
          end
          next
        end

        # special-case "today"
        if days_ago == 1
          sort_by_time(upd_chapters, :first_update)
          first_last = :first
          new_after = early_time
          show_last_author = false
          colon_message = "New updates #{early_time.strftime('%m-%d')}:"
          list_style = '1'
          show_unread_link = true
        else
          sort_by_time(upd_chapters, :last_update)
          first_last = :last
          new_after = today_time + 3
          show_last_author = :unless_completed
          colon_message = "Last updated #{early_time.strftime('%m-%d')}:"
          list_style = false
          show_unread_link = false
        end

        # output the relevant day's sreport list
        report_list(upd_chapters, first_last: first_last, completed_before: late_time, new_after: new_after, show_last_author: show_last_author, show_unread_link: show_unread_link, spoiler_box: false, list_style: list_style, message: colon_message)

        # add "today" spoiler boxes
        next unless days_ago == 1

        # New threads
        new_chapters = upd_chapters.select { |chapter_thing| chapter_thing[:chapter].time_new >= early_time }
        if new_chapters.present?
          report_list(new_chapters, first_last: :first, completed_before: late_time, new_after: early_time, spoiler_box: 'New threads', message: colon_message)
        end

        # Dreamwidth threads
        dw_upd_chapters = upd_chapters.select { |chapter_thing| GlowficSiteHandlers::DreamwidthHandler.handles?(chapter_thing[:chapter]) }
        if dw_upd_chapters.present?
          report_list(dw_upd_chapters, first_last: :first, completed_before: late_time, new_after: early_time, spoiler_box: 'Dreamwidth threads', message: colon_message)
        end

        # Today, not yesterday
        not_yesterdays = upd_chapters.select { |chapter_thing| !chapter_thing[:yesterday] }
        if not_yesterdays.present?
          report_list(not_yesterdays, first_last: :first, completed_before: late_time, new_after: early_time, spoiler_box: 'Today, not yesterday', message: colon_message)
        end

        # Continuities
        sec_upd_chapters = upd_chapters.select {|chapter_thing| chapter_thing[:chapter].sections.present? }
        sec_upd_chapters.sort! do |chapter_thing1, chapter_thing2|
          sect_diff = chapter_thing1[:chapter].sections.map {|thing| (thing.is_a?(String) ? thing.downcase : thing)} <=> chapter_thing2[:chapter].sections.map {|thing| (thing.is_a?(String) ? thing.downcase : thing)}
          next sect_diff unless sect_diff == 0

          update_time2 = chapter_thing2[:chapter].time_new if chapter_thing2[:first_update] == chapter_thing2[:chapter].entry
          update_time1 = chapter_thing1[:chapter].time_new if chapter_thing1[:first_update] == chapter_thing1[:chapter].entry
          update_time2 ||= chapter_thing2[:first_update].time
          update_time1 ||= chapter_thing1[:first_update].time
          next update_time2 <=> update_time1
        end
        if sec_upd_chapters.present?
          report_list(sec_upd_chapters, first_last: :first, completed_before: late_time, new_after: early_time, show_sections: true, spoiler_box: 'Continuities', message: colon_message)
        end
      end
      report_output "[url=http://alicorn.elcenia.com/board/viewtopic.php?f=10&t=498#p25059]Official moiety list[/url] ([url=http://alicorn.elcenia.com/board/viewtopic.php?f=10&t=498#p25060]rainbow[/url])"
      report_output!

      done_msg = false
      chapter_list.each do |chapter|
        next if done.include?(chapter)
        unless done_msg
          LOG.error "---- ERROR:"
          done_msg = true
        end
        LOG.error "#{chapter}"
      end
      @errors.each do |error|
        unless done_msg
          LOG.error "---- ERROR:"
          done_msg = true
        end
        LOG.error "#{error}"
      end
    end
  end

  class RailsHandler < OutputHandler
    def initialize(options={})
      super options
      @icon_cache = {}
      @char_cache = {}
      @gallery_cache = {}
      @user_cache = {}
      @usermoiety_cache = {}
      @boardsection_cache = {}
      @board_cache = {}
      @post_cache = {}
      @reply_cache = {}
      @post_not_skips = {}
      @user_moiety_rewrite = {}
      @confirm_dupes = options.fetch(:confirm_dupes, DEBUGGING)
    end

    def character_for_journal(journal)
      return @char_cache[journal.unique_id] if @char_cache.key?(journal.unique_id)
      return nil unless journal.unique_id
      user = user_for_journal(journal)
      chars = nil
      journal.screenname = journal.unique_id.sub('dreamwidth#', '') if !journal.screenname.present? && journal.unique_id.start_with?('dreamwidth#')

      chars = Character.where(user_id: user.id, screenname: journal.screenname) if journal.screenname.present?
      chars = Character.where(user_id: user.id, name: journal.name) if journal.name.present? && !chars.present?
      unless chars.present?
        # unique_ids:
        # dreamwidth#{journal_id}
        # constellation#user#{user_id}
        # constellation#{character_id}
        skip_creation = false
        if journal.unique_id.start_with?('constellation#user#')
          chars = [] # character is nil if it's a user post
          skip_creation = true
        elsif journal.unique_id.start_with?('constellation#')
          char_id = journal.unique_id.sub('constellation#', '')
          chars = Character.where(user_id: user.id, id: char_id)
        end

        unless skip_creation or chars.present?
          char = Character.create!(user: user, name: journal.name, screenname: journal.screenname)
          LOG.info "- Created character '#{journal.name}' for author '#{user.username}'."
        end
      end
      char ||= chars.first
      @char_cache[journal.unique_id] = char
      if journal.default_face.present?
        default_icon = icon_for_face(journal.default_face)
        if char.present? && default_icon.present?
          char.update_attributes(default_icon: default_icon)
          LOG.debug "- Set a default icon for #{char.name}: #{default_icon.id}"
        end
      else
        LOG.warn("- Character has no default face: #{journal}")
      end
      char
    end
    def gallery_for_journal(journal)
      return @gallery_cache[journal.unique_id] if @gallery_cache.key?(journal.unique_id)
      char = character_for_journal(journal)
      return nil unless char
      if char.galleries.empty?
        LOG.debug "- Created gallery for #{journal.name}"
        char.galleries.build(user: char.user, name: journal.name)
        char.save!
      else
        LOG.debug "- #{journal.name} has an uncached gallery; using it. (ID #{char.galleries.first.id})"
      end
      @gallery_cache[journal.unique_id] = char.galleries.first
    end
    def user_for_journal(journal, options={})
      return @user_cache[journal.unique_id] if @user_cache.key?(journal.unique_id)
      return nil unless journal.unique_id
      set_coauthors = options.key?(:set_coauthors) ? options[:set_coauthors] : @set_coauthors
      moieties = journal.moieties
      moieties = ['Unknown Author'] unless moieties.present?
      moiety = moieties.first
      cached_moiety = moieties.find {|moiety_val| @usermoiety_cache.key?(moiety_val) }
      return @usermoiety_cache[cached_moiety] if cached_moiety
      LOG.warn("- Character has many moieties (#{journal.moiety})") if moieties.length > 1

      users = User.where('lower(username) = ?', moieties.map(&:downcase))
      unless users.present?
        rewrites = moieties.map{|moiety_i| @user_moiety_rewrite.keys.detect{|key| key.downcase == moiety_i.downcase} }.compact.map{|key| @user_moiety_rewrite[key].downcase}
        if rewrites.present?
          users = User.where('lower(username) = ?', rewrites)
        end
      end
      unless users.present?
        LOG.info "- No user(s) found for moiet" + (moieties.length == 1 ? "y '#{moieties.first}'" : "ies: #{moieties * ', '}")
        puts "Please enter a user ID or username for the user."
        userthing = STDIN.gets.chomp
        if userthing[/[A-Za-z]/]
          users = User.where('lower(username) = ?', userthing)
        else
          users = User.where(id: userthing.to_i)
        end

        if users.present?
          @user_moiety_rewrite[moieties.first.downcase] = users.username
        end

        unless users.present?
          puts "No user(s) found for '#{userthing}'. Would you like to create a new user for this moiety? (#{moiety}) (y/N)"
          while (input = STDIN.gets.chomp.strip.downcase) && input != 'y' && input != 'n' && input != ''
            puts "Unrecognized input."
          end
          input = 'n' if input.empty?
          if input == 'y'
            user = User.create!(username: moiety, password: moiety.downcase, email: moiety.downcase.gsub(/[^\w\-\.+]/, '') + '@example.com')
            LOG.info "- User created for #{moiety}."
          else
            LOG.warn "- Skipping user for #{moiety}. Will likely cause errors."
          end
        end
      end
      user ||= users.first
      if set_coauthors
        board = board_for_chapterlist(@chapter_list)
        if board.present? && board.creator_id != user.id && !board.coauthors.include?(user)
          board.coauthors << user
          LOG.info "- Added coauthor to board: #{user.id}"
        end
      end
      @user_cache[journal.unique_id] = user
      @usermoiety_cache[user.try(:username).try(:downcase)] = user
    end
    def icon_for_face(face)
      return nil unless face.present? and face.imageURL.present?
      return @icon_cache[face.unique_id] if @icon_cache.key?(face.unique_id)
      user = user_for_journal(face.journal)
      gallery = gallery_for_journal(face.journal)
      icon = Icon.where(url: face.imageURL, user_id: user.id).includes(:galleries).select{|icon_i| icon_i.galleries.include?(gallery)}.first
      unless icon.present?
        icon = Icon.where(url: face.imageURL, user_id: user.id).first
        gallery.icons << icon if gallery && icon.present?
      end
      unless icon.present?
        gallery = gallery_for_journal(face.journal)
        icon = Icon.create!(user: user, url: face.imageURL, keyword: face.keyword)
        gallery.icons << icon if gallery
      end
      @icon_cache[face.unique_id] = icon
    end

    def board_for_chapterlist(chapter_list)
      return @board_cache[chapter_list] if @board_cache.key?(chapter_list)
      chapter_list.group ||= @group
      board_name = FIC_NAMESTRINGS[chapter_list.group]
      boards = Board.where('lower(name) = ?', board_name.downcase)
      unless boards.present?
        first_user = user_for_journal(chapter_list.characters.first, set_coauthors: false)
        board = Board.create!(name: board_name, creator: first_user)
        LOG.info "- Created board for chapterlist, name '#{board_name}' with creator ID #{first_user.id}"
        @set_coauthors = true if @set_coauthors == :if_new_board
      end
      @set_coauthors = false if @set_coauthors == :if_new_board
      board ||= boards.first
      @set_coauthors = board.posts.empty? if @set_coauthors == :if_empty_board
      @board_cache[chapter_list] = board
    end
    def boardsection_for_chapter(chapter)
      return nil unless chapter.sections.present?
      section_string = chapter.sections * ' > '
      board = board_for_chapterlist(chapter.chapter_list)
      @boardsection_cache[board] ||= {}
      return @boardsection_cache[board][section_string] if @boardsection_cache[board].key?(section_string)
      boardsections = BoardSection.where('lower(name) = ?', section_string.downcase).where(board_id: board.id)
      unless boardsections.present?
        boardsection = BoardSection.create!(board: board, name: section_string, section_order: board.board_sections.count)
      end
      boardsection ||= boardsections.first
      @boardsection_cache[board][section_string] = boardsection
    end
    def postgroup_for_chapter(chapter)
      return nil unless chapter.present?
      postgroup = boardsection_for_chapter(chapter)
      postgroup = board_for_chapterlist(chapter.chapter_list) unless postgroup.present?
      LOG.error "-- Failed to find a 'postgroup' for #{chapter}" unless postgroup
      postgroup
    end
    def do_writables_from_message(writable, message)
      writable.user = user_for_journal(message.journal)
      writable.character = character_for_journal(message.journal)
      writable.icon = icon_for_face(message.face)
      writable.content = message.content.strip
      writable.created_at = message.time
      writable.updated_at = message.edittime if message.edittime.present?
      writable.updated_at ||= writable.created_at
      writable
    end
    def post_for_entry?(entry, board=nil)
      post_cache_id = entry.id + (entry.chapter.thread ? "##{entry.chapter.thread}" : '') + '#entry'
      unless @post_cache.key?(post_cache_id)
        chapter = entry.chapter
        postgroup = postgroup_for_chapter(chapter)
        lowercase_title = chapter.entry_title.downcase
        matching_posts = postgroup.posts.where('lower(subject) = ?', lowercase_title)
        matching_posts = matching_posts.not(id: @post_not_skips[lowercase_title]) if @post_not_skips.key?(lowercase_title)

        matching_posts = matching_posts.select {|post| post.replies.length == chapter.replies.length && (post.replies.count == 0 || post.replies.order('id asc').first.content.strip.gsub(/\<[^\<\>]*?\>/, '').gsub(/\r?\n/, '').gsub(/\s{2,}/, ' ') == chapter.replies.first.content.strip.gsub(/\<[^\<\>]*?\>/, '').gsub(/\r?\n/, '').gsub(/\s{2,}/, ' ')) }
        # If they're the same length, check if they have the same content for their first reply (skipping HTML tags and linebreaks and dupe spaces).

        if matching_posts.present?
          matching_post_ids = matching_posts.map(&:id)
          @msgs << "- Chapter is duplicate. IDs: #{matching_post_ids * ', '}."
          if @confirm_dupes
            first_reply = chapter.replies.first
            puts "First reply content: #{first_reply.content}" if first_reply.present?
            puts "Please verify if this is a duplicate (Y) and should be skipped or not (n) and should be reprocessed."
            while (input = STDIN.gets.chomp.strip.downcase) && input != 'y' && input != 'n' && input != ''
              puts "Unrecognized input."
            end
            input = 'y' if input.empty?
          else
            input = 'y'
          end
          if input == 'y'
            @msgs.last << " Noted duplicate."
            @post_cache[post_cache_id] = matching_posts.first
          else
            @msgs.last << " Noted not duplicates."
            @post_not_skips[lowercase_title] ||= []
            @post_not_skips[lowercase_title] += matching_post_ids
          end
        end
      end
      @post_cache.key?(post_cache_id)
    end
    def post_for_entry(entry, board=nil)
      board ||= board_for_chapterlist(entry.chapter_list)
      post_cache_id = entry.id + (entry.chapter.thread ? "##{entry.chapter.thread}" : '') + '#entry'
      return @post_cache[post_cache_id] if @post_cache.key?(post_cache_id)
      chapter = entry.chapter
      post = Post.new
      post.board = board
      post.subject = chapter.entry_title
      post.status = chapter.time_completed ? Post::STATUS_COMPLETE : (chapter.time_hiatus ? Post::STATUS_HIATUS : Post::STATUS_ACTIVE)
      post.section = boardsection_for_chapter(chapter)
      post.section_order = post.section.posts.count if post.section.present? && !@skip_post_ordering

      do_writables_from_message(post, entry)
      board.created_at = post.created_at unless board.created_at
      post.tagged_at = post.edited_at = post.updated_at
      post.last_user = post.user
      post.save!

      @post_cache[post_cache_id] = post
    end
    def reply_for_comment(comment, threaded=false, thread_id=nil, do_update=false)
      reply_cache_id = comment.chapter.entry.id + '#' + comment.id
      return @reply_cache[reply_cache_id] if @reply_cache.key?(reply_cache_id)

      post = post_for_entry(comment.chapter.entry)
      reply = post.replies.build
      reply.thread_id = thread_id if threaded && thread_id
      reply.skip_notify = true

      do_writables_from_message(reply, comment)

      reply.skip_post_update = !do_update

      if threaded && comment.parent == comment.chapter.entry
        reply.thread_id = reply.id
        reply.skip_post_update = true
        reply.skip_notify = true
      end
      @reply_cache[reply_cache_id] = reply
    end

    def output(options={})
      chapter_list = options.include?(:chapter_list) ? options[:chapter_list] : (@chapters ? @chapters : nil)
      (LOG.fatal "No chapters given!" and return) unless chapter_list
      @chapter_list = chapter_list
      @skip_post_ordering = options.include?(:skip_post_ordering) ? options[:skip_post_ordering] : false
      @set_coauthors = options.include?(:set_coauthors) ? options[:set_coauthors] : :if_empty_board # alternatively :if_new_board

      puts "Would you like to (1) do detected non-duplicate chapters, (2) do chapters with inputted IDs or (3) prompt for each chapter?"
      while (input = STDIN.gets.chomp.strip.downcase) && input != '1' && input != '2' && input != '3'
        puts "Unrecognized input."
      end
      chapter_prompt = nil
      chapter_prompt = :do_all if input == '1'
      chapter_prompt = :do_ids if input == '2'
      chapter_prompt = :prompt if input == '3'

      if chapter_prompt == :do_ids
        puts "Chapter faux-IDs: #{chapter_list.map(&:fauxID).uniq.compact * ', '}"
        puts "Please input the IDs (format: community#entry-id(#thread-id), constellation#entry-id), asterisks allowed at the end of phrases, separated by spaces:"
        input = STDIN.gets.chomp.strip.downcase
      end

      Post.record_timestamps = false
      Reply.record_timestamps = false
      chapter_count = chapter_list.count
      chapter_list.each_with_index do |chapter, i|
        (LOG.error "(#{i}/#{chapter_count}) Chapter has no entry: #{chapter}" and next) unless chapter.entry.present?
        if chapter_prompt == :prompt
          puts "Chapter: #{chapter}; should do? (Y/n)"
          while (input = STDIN.gets.chomp.strip.downcase) && input != 'y' && input != 'n' && input != ''
            puts "Unrecognized input."
          end
          if input == 'n'
            LOG.info "(#{i}/#{chapter_count}) Skipping #{chapter} at user input"
            next
          end
        elsif chapter_prompt == :do_ids
          chapter_fauxid = chapter.fauxID
          found = false
          chapter_do.each do |chapter_id|
            if chapter_id.strip.downcase == chapter_fauxid.strip.downcase
              found = true
              break
            end
            next unless chapter_id.end_with?('*')
            chapter_id_match = chapter_id[0..-2]
            if chapter_fauxid.start_with?(chapter_id_match)
              found = true
              break
            end
          end
          unless found
            LOG.info "(#{i}/#{chapter_count}) Skipping #{chapter}; fauxid (#{chapter_fauxid}) doesn't match list."
            next
          end
        end
        threaded = false
        ([chapter.entry] + chapter.replies).each do |reply|
          next if reply.children.length <= 1
          if reply.children.length == 2 && reply.children.first.children.empty?
            reply.children.last.parent = reply.children.first
            (LOG.info "unbranched #{reply}" and next) if reply.children.length <= 1
            LOG.error "unbranching failed somehow? reply: #{reply}, children: #{reply.children}, children parents: #{reply.children.map(&:parent)}"
          end
          threaded = true
        end

        @msgs = []
        LOG.info "(#{i+1}/#{chapter_count}) Chapter #{chapter}"

        board = board_for_chapterlist(chapter_list)
        (@msgs.each {|msg| LOG.info msg} and next) if post_for_entry?(chapter.entry, board)
        post = post_for_entry(chapter.entry, board)
        thread_id = nil
        chapter.replies.each_with_index do |reply, y|
          repl = reply_for_comment(reply, threaded, thread_id, reply == chapter.replies.last)
          thread_id = repl.thread_id if threaded
          if (y+1) % 100 == 0
            old_status = post.status
            repl.skip_notify = true
            repl.skip_post_update = false
            post.save!
            repl.save!
            board.update_column(:updated_at, post.updated_at) if board.updated_at.present? && post.updated_at.present? && post.updated_at > board.updated_at
            post.update_column(:status, old_status)
          end
        end

        old_status = post.status
        post.save!
        board.update_column(:updated_at, post.updated_at) if board.updated_at.present? && post.updated_at.present? && post.updated_at > board.updated_at
        post.update_column(:status, old_status)
      end
      Post.record_timestamps = true
      Reply.record_timestamps = true
      LOG.info "Finished outputting #{@group} to Rails."
    end
  end
end
