module GlowficOutputHandlers
  require 'model_methods'
  require 'models'
  require 'uri'
  require 'erb'
  include GlowficEpubMethods
  include GlowficEpub::PostType
  
  class OutputHandler
    include GlowficEpub
    include GlowficEpubMethods
    def initialize(options={})
      @chapters = options[:chapters] if options.key?(:chapters)
      @chapters = options[:chapter_list] if options.key?(:chapter_list)
      @group = options[:group] if options.key?(:group)
    end
  end
  
  class EpubHandler < OutputHandler
    include ERB::Util
    
    def initialize(options={})
      super options
      require 'eeepub'
      @group_folder = File.join('output', 'epub', @group.to_s)
      @style_folder = File.join(@group_folder, 'style')
      @html_folder = File.join(@group_folder, 'html')
      @images_folder = File.join(@group_folder, 'images')
      @replies_per_split = (options.key?(:replies_per_split) ? options[:replies_per_split] : 200)
      @min_replies_in_split = (options.key?(:min_replies_in_split) ? options[:min_replies_in_split] : 50)
      @do_epub = (options.key?(:do_epub) ? options[:do_epub] : true)
      FileUtils::mkdir_p @style_folder
      FileUtils::mkdir_p @html_folder
      FileUtils::mkdir_p @images_folder
      @face_path_cache = {}
      @paths_used = []
    end
    
    def get_face_path(face)
      face_url = face if face.is_a?(String)
      face_url = face.imageURL if face.is_a?(Face)
      return "" if face_url.nil? or face_url.empty?
      return @face_path_cache[face_url] if @face_path_cache.key?(face_url)
      LOG.debug "get_face_path('#{face_url}')"
      
      face_url = face_url.gsub(' ', '%20').gsub('!', '%21').gsub('$', '%24').gsub("'", '%27').gsub('(', '%28').gsub(')', '%29').gsub('*', '%2A').gsub('+', '%2B').gsub(',', '%2C').gsub('=', '%3D').gsub('[', '%5B').gsub(']', '%5D')
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
      test_ext = "." + test_ext if test_ext and not test_ext.empty?
      test_filename = 'img-' + filename.sub("#{test_ext}", "").gsub(/[^a-zA-Z0-9_\-]+/, "_")
      i = 0
      relative_file = sanitize_local_path(File.join('images', uri.host, test_filename + test_ext))
      while @paths_used.include?(relative_file)
        i += 1
        temp_filename = "#{test_filename}_#{i}"
        relative_file = sanitize_local_path(File.join('images', uri.host, temp_filename + test_ext))
        LOG.debug "There was an issue with the previous file. Trying alternate path: #{temp_filename + test_ext}"
      end
      try_down = download_file(face_url, save_path: File.join(save_path, relative_file), replace: false)
      unless try_down
        @face_path_cache[face_url] = "" #So it doesn't error multiple times for a single icon
        return ""
      end
      @paths_used << relative_file
      
      @files << {File.join(save_path, relative_file) => File.join('EPUB', File.dirname(relative_file))}
      @face_path_cache[face_url] = File.join("..", relative_file)
    end
    def get_comment_path(comment_url)
      return comment_url unless comment_url.start_with?('http://') or comment_url.start_with?('https://')
      return comment_url unless comment_url['.dreamwidth.org/'] or comment_url['vast-journey-9935.herokuapp.com/']
      comment_url = comment_url.gsub('&amp;', '&')
      short_url = Chapter.shortenURL(comment_url)
      fragment = (comment_url['#'] ? comment_url.split('#').last : '')
      if comment_url['.dreamwidth.org/']
        thread_thing = short_url.split('?').first.split('#').first
        comment_id = fragment[/(comment|cmt)-?(\d+)/].try(:split, /t-?/).try(:last)
        comment_id ||= short_url.split('thread=').last.split('&').first.split('#').first if short_url[/(\?|&)thread=(\d+)/]
        comment_id = "cmt" + comment_id if comment_id
      elsif comment_url['vast-journey-9935.herokuapp.com/']
        thread_thing = short_url.split('/').first
        comment_id = fragment[/reply-(\d+)/].try(:split, '-').try(:last)
        comment_id ||= short_url.split('/replies/').last.split('?').first.split('#').first if short_url[/\/replies\/\d+/]
      else
        LOG.error "chapter was not from dreamwidth or constellation? #{comment_url}"
        return comment_url
      end
      
      comment_path = nil
      @chapters.each do |chapter|
        next unless chapter.shortURL.start_with?(thread_thing)
        next if chapter.thread.present? && !comment_id.present?
        if comment_id
          reply = chapter.replies.detect {|reply| reply.id == comment_id}
          if reply
            if reply == chapter.replies.first
              comment_path = get_chapter_path_bit(chapter: chapter)
            else
              comment_path = get_chapter_path_bit(chapter: chapter) + "#comment-#{reply.id}"
            end
          else
            next
          end
        end
        unless comment_path
          comment_path = get_chapter_path_bit(chapter: chapter)
        end
        break if comment_path
      end
      comment_path || comment_url
    end
    def get_chapter_path(options = {})
      chapter = options.is_a?(Chapter) ? options : (options.is_a?(Hash) && options.key?(:chapter) ? options[:chapter] : nil)
      chapter_url = chapter.url if chapter
      chapter_url ||= options.is_a?(String) ? options : (options.is_a?(Hash) && options.key?(:chapter_url) ? options[:chapter_url] : nil)
      group = options.key?(:group) ? options[:group] : @group
      
      save_path = File.join(@html_folder, get_chapter_path_bit(options))
    end
    def get_relative_chapter_path(options = {})
      chapter = options.is_a?(Chapter) ? options : (options.is_a?(Hash) && options.key?(:chapter) ? options[:chapter] : nil)
      chapter_url = chapter.url if chapter
      chapter_url ||= options.is_a?(String) ? options : (options.is_a?(Hash) && options.key?(:chapter_url) ? options[:chapter_url] : nil)
      
      File.join('EPUB', 'html', get_chapter_path_bit(options))
    end
    def get_chapter_path_bit(options = {})
      chapter = options.is_a?(Chapter) ? options : (options.is_a?(Hash) && options.key?(:chapter) ? options[:chapter] : nil)
      chapter_url = chapter.url if chapter
      chapter_url ||= options.is_a?(String) ? options : (options.is_a?(Hash) && options.key?(:chapter_url) ? options[:chapter_url] : nil)
      
      thread = get_url_param(chapter_url, 'thread')
      thread = nil if thread.nil? or thread.empty?
      
      uri = URI.parse(chapter_url)
      save_file = uri.host.sub('.dreamwidth.org', '').sub('vast-journey-9935.herokuapp.com', 'constellation')
      uri_path = uri.path
      uri_path = uri_path[1..-1] if uri_path.start_with?('/')
      save_file += '-' + uri_path.sub('.html', '') + (thread ? "-#{thread}" : '') + '.html'
      save_path = save_file.gsub('/', '-')
      File.join(save_path)
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
    
    def html_from_navbits(navbits)
      html = "<ol>\n"
      if navbits.key?(:_order)
        navbits[:_order].each do |key|
          html << "<li>#{key}"
          sub_html = html_from_navbits(navbits[key])
          html << "\n" << sub_html if sub_html.present?
          html << "</li>\n"
        end
      elsif navbits.key?(:_contents)
        navbits[:_contents].each do |content|
          html << "<li><a href='" << File.join('html', get_chapter_path_bit(chapter: content[:chapter])) << "'>#{h(content[:label])}</a></li>\n"
        end
        puts "navbits contents are empty: #{navbits}" if navbits[:_contents].empty?
      else
        puts "navbits has nothing in it: #{navbits}"
      end
      html << "</ol>\n"
      html = "" if html == "<ol>\n</ol>\n"
      html
    end
    
    def get_message_orders(chapter) # [0] is the 0th, [1] is the 2nd pos, value is -1 if entry else position in chapter.replies
      @message_orders ||= {}
      chapter_pathbit = get_chapter_path_bit(chapter)
      return @message_orders[chapter_pathbit] if @message_orders.key?(chapter_pathbit)
      
      chapter_order = []
      message = chapter.entry
      while message
        message_num = (message == chapter.entry ? -1 : chapter.replies.index(message))
        chapter_order << message_num unless chapter_order.include?(message_num)
        new_msg = nil
        
        message.children.each do |child|
          next if chapter_order.include?(chapter.replies.index(child))
          new_msg = child
          break
        end
        unless new_msg
          new_msg = message.parent
        end
        
        message = new_msg
      end
      
      warned = false
      chapter.replies.each do |message|
        message_num = (message == chapter.entry ? -1 : chapter.replies.index(message))
        unless chapter_order.include?(message_num)
          chapter_order << message_num
          LOG.error "Chapter #{chapter} didn't get all messages via depth traversal." unless warned
          warned = true
        end
      end
      
      @message_orders[chapter_pathbit] = chapter_order
      chapter_order
    end
    
    def output(chapter_list=nil)
      chapter_list = @chapters if chapter_list.nil? and @chapters
      (LOG.fatal "No chapters given!" and return) unless chapter_list
      
      template_chapter = ''
      open('template_chapter.erb') do |file|
        template_chapter = file.read
      end
      template_message = ''
      open('template_message.erb') do |file|
        template_message = file.read
      end
      
      style_path = File.join(@style_folder, 'default.css')
      open('style.css', 'r') do |style|
        open(style_path, 'w') do |css|
          css.write style.read
        end
      end
      
      @files = [{style_path => 'EPUB/style'}]
      
      @show_authors = FIC_SHOW_AUTHORS.include?(@group)
      @changed = false
      
      @save_paths_used = []
      @rel_paths_used = []
      chapter_count = chapter_list.count
      chapter_list.each_with_index do |chapter, i|
        @chapter = chapter
        (LOG.error "(#{i+1}/#{chapter_count}) #{chapter}: No entry for chapter." and next) unless chapter.entry
        (LOG.info "(#{i+1}/#{chapter_count}) #{chapter}: Chapter is entry-only.") if chapter.replies.nil? or chapter.replies.empty?
        save_path = get_chapter_path(chapter: chapter, group: @group)
        (LOG.info "(#{i+1}/#{chapter_count}) #{chapter}: Duplicate chapter not added again" and next) if @save_paths_used.include?(save_path)
        rel_path = get_relative_chapter_path(chapter: chapter)
        
        @files << {save_path => File.dirname(rel_path)}
        @save_paths_used << save_path
        @rel_paths_used << rel_path
        
        if chapter.processed_epub?
          chapter.processed_epub = File.file?(save_path)
          LOG.error "#{chapter}: cached data was not found." unless chapter.processed_epub?
        end
        
        (LOG.info "(#{i+1}/#{chapter_count}) #{chapter}: cached data used." and next) if chapter.processed_epub?
        
        @messages = get_message_orders(chapter).map{|count| (count >= 0 ? chapter.replies[count] : chapter.entry)}
        
        @message_htmls = @messages.map do |message|
          @message = message
          erb = ERB.new(template_message, 0, '-')
          b = binding
          erb.result b
        end
        
        erb = ERB.new(template_chapter, 0, '-')
        b = binding
        page_data = erb.result b
        
        
        page = Nokogiri::HTML(page_data)
        page.css('img').each do |img_element|
          img_src = img_element.try(:[], :src)
          next unless img_src
          next unless img_src.start_with?('http://') or img_src.start_with?('https://')
          img_element[:src] = get_face_path(img_src)
        end
        page.css('a').each do |a_element|
          a_href = a_element.try(:[], :href)
          next unless a_href
          a_element[:href] = get_comment_path(a_href)
        end
        
        open(save_path, 'w') do |file|
          file.write page.to_xhtml(indent_text: '', encoding: 'UTF-8')
        end
        chapter.processed_epub = true
        @changed = true
        LOG.info "(#{i+1}/#{chapter_count}) Did chapter #{chapter}"
      end
      
      nav_bits = {}
      contents_allowed = @rel_paths_used
      chapter_list.each do |chapter|
        prev_bit = nav_bits
        chapter.sections.each do |section|
          prev_bit[:_order] ||= []
          prev_bit[:_order] << section unless prev_bit[:_order].include?(section)
          prev_bit[section] ||= {}
          prev_bit = prev_bit[section]
        end
        prev_bit[:_contents] ||= []
        if contents_allowed.present? && !contents_allowed.include?(get_relative_chapter_path(chapter: chapter))
          LOG.info "Ignoring chapter in NAV: #{chapter}. Not in contents_allowed."
        else
          prev_bit[:_contents] << {label: chapter.title, chapter: chapter}
        end
      end
      
      open(File.join(@group_folder, 'toc.html'), 'w') do |toc|
        toc.write html_from_navbits(nav_bits)
      end
      
      nav_array = navify_navbits(nav_bits)
      
      @files.each do |thing|
        thing.keys.each do |key|
          next if key.start_with?('/')
          thing[File.join(Dir.pwd, key)] = thing[key]
          thing.delete(key)
        end
      end
      
      if @do_epub
        group_name = @group
        uri = URI.parse(FIC_TOCS[group_name])
        uri_host = uri.host
        uri_host = '' unless uri_host
        files_list = @files
        epub_path = "output/epub/#{@group}.epub"
        epub = EeePub.make do
          title FIC_NAMESTRINGS[group_name]
          creator FIC_AUTHORSTRINGS[group_name]
          publisher uri_host
          date DateTime.now.strftime('%Y-%m-%d')
          identifier FIC_TOCS[group_name], scheme: 'URL'
          uid "glowfic-#{group_name}"
          
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
    def csscol_to_rgb(csscol)
      csscol = csscol.strip.upcase
      csscol = csscol[1..-1] if csscol.start_with?('#')
      if csscol.length == 3
        css_r = csscol[0]
        css_g = csscol[1]
        css_b = csscol[2]
      elsif csscol.length == 6
        css_r = csscol[0..1]
        css_g = csscol[2..3]
        css_b = csscol[4..5]
      else
        raise(ArgumentError, "csscol is not a CSS hex color")
      end
      r = @hex.index(css_r[0]) * 16 + @hex.index(css_r[-1])
      g = @hex.index(css_g[0]) * 16 + @hex.index(css_g[-1])
      b = @hex.index(css_b[0]) * 16 + @hex.index(css_b[-1])
      [r,g,b]
    end
    def rgb_to_hsl(r, g=nil, b=nil)
      if r.is_a?(Array)
        g = r[1]
        b = r[2]
        r = r[0]
      end
      
      r = r.to_f / 255
      g = g.to_f / 255
      b = b.to_f / 255
      max = [r,g,b].max
      min = [r,g,b].min
      l = s = h = (max + min) / 2.0
      
      if (max == min)
        h = s = 1.0 #hack so gray gets sent to the end
      else
        d = max - min
        s = (l > 0.5) ? d / (2.0 - max - min) : d / (max + min)
        case (max)
        when r
          h = (g - b) / d + (g < b ? 6.0 : 0.0)
        when g
          h = (b - r) / d + 2.0
        when b
          h = (r - g) / d + 4.0
        end
        h = h / 6.0
      end
      
      [h,s,l]
    end
    def hsl_comp(hsl1, hsl2)
      if hsl1[0] == hsl2[0]
        hsl1[2] <=> hsl2[2]
      else
        hsl1[0] <=> hsl2[0]
      end
    end
    def rainbow_comp(thing1, thing2)
      @thing1_pri = thing1.match(@flag_pri_scan)[1] if thing1[@flag_pri_scan]
      @thing1_sec = thing1.match(@flag_sec_scan)[1] if thing1[@flag_sec_scan]
      @thing2_pri = thing2.match(@flag_pri_scan)[1] if thing2[@flag_pri_scan]
      @thing2_sec = thing2.match(@flag_sec_scan)[1] if thing2[@flag_sec_scan]
      @thing1_pri ||= thing1
      @thing1_sec ||= thing1
      @thing2_pri ||= thing2
      @thing2_sec ||= thing2
      
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
      first_last = options.key?(:first) ? (options[:first] != false ? :first : :last) : (options.key?(:last) ? (options[:last] != false ? :last : :first) : (options.key?(:first_last) ? options[:first_last] : :first))
      show_completed_before = options.key?(:completed) ? options[:completed] : (options.key?(:completed_before) ? options[:completed_before] : (DateTime.new(@date.year, @date.month, @date.day, 10, 0, 0) - 1))
      show_completed_before = 0 unless show_completed_before
      show_hiatus_before = show_completed_before
      show_new_after = options.key?(:early) ? options[:early] : (options.key?(:new_after) ? options[:new_after] : (DateTime.new(@date.year, @date.month, @date.day, 10, 0, 0) - 1))
      show_last_update_time = options.key?(:show_last_update_time) ? options[:show_last_update_time] : false
      show_sections = options.key?(:show_sections) ? options[:show_sections] : false
      show_last_author = options.key?(:show_last_author) ? options[:show_last_author] : false
      
      chapter = chapterthing[:chapter]
      first_update = chapterthing[:first_update]
      last_update = chapterthing[:last_update]
      latest_update = chapterthing[:latest_update]
      completed = (chapter.time_completed and chapter.time_completed <= show_completed_before)
      hiatus = (chapter.time_hiatus and chapter.time_hiatus <= show_hiatus_before)
      url_thing = (first_last == :first ? first_update : (first_last == :last ? last_update : latest_update))
      @errors << "#{chapter} has no url_thing! (first_last: #{first_last})" unless url_thing
      
      show_last_author = !completed if show_last_author == :unless_completed
      
      if chapter.report_flags and not chapter.report_flags_processed?
        chapter.report_flags = chapter.report_flags.scan(@col_scan).map{|thing| thing[0] }.uniq.map do |thing|
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
        end.sort{|thing1, thing2| rainbow_comp(thing1, thing2) }.join(' ').strip.gsub(/[\(\)]/, '')
        chapter.report_flags_processed = true
      end
      
      if chapter.title_extras.present? and not chapter.report_flags.present?
        chapter.report_flags = chapter.title_extras.scan(@flag_scan).map{|thing| thing[0] }.uniq.sort{|thing1, thing2| rainbow_comp(thing1, thing2) }.join(' ').strip.gsub(/[\(\)]/, '')
        chapter.title_extras = chapter.title_extras.gsub(@flag_scan, '')
      end
      
      chapter.report_flags = "" unless chapter.report_flags
      
      show_last_author = false unless latest_update.author_str
      
      @errors << "#{chapter}: both completed and hiatused" if completed and hiatus
      
      section_string = ''
      if show_sections && chapter.sections.present?
        str = chapter.sections * ' > '
        @cont_replace.each {|key, val| str = str.sub(key, val)}
        section_string = ' (' + str + ')'
      end
      str = "[*]"
      str << '[size=85]' + chapter.report_flags.strip + '[/size] ' if chapter.report_flags and not chapter.report_flags.strip.empty?
      str << "[url=#{url_thing.permalink}]" if url_thing
      str << '[color=#9A534D]' if hiatus
      str << '[color=goldenrod]' if completed
      str << "#{chapter.entry_title}"
      str << '[/color]' if completed
      str << '[/color]' if hiatus
      str << '[/url]' if url_thing
      str << section_string
      str << ',' unless chapter.entry_title and chapter.entry_title[/[?,.!;…\-–—]$/] #ends with punctuation (therefore 'don't add a comma')
      str << ' '
      str << "#{chapter.title_extras || '(no extras)'}"
      str << ', new' if chapter.entry.time >= show_new_after
      str << ' (' if show_last_author or show_last_update_time
      str << "last post by #{latest_update.author_str}" if show_last_author
      str << ', ' if show_last_author and show_last_update_time
      str << 'last updated ' + latest_update.time.strftime((latest_update.time.year != @date.year ? '%Y-' : '') + '%m-%d %H:%M') if show_last_update_time
      str << ')' if show_last_author or show_last_update_time
      return str
    end
    def output(options = {})
      chapter_list = options.include?(:chapter_list) ? options[:chapter_list] : @chapters
      show_earlier = options.include?(:show_earlier) ? options[:show_earlier] : false
      @cont_replace = options.include?(:cont_replace) ? options[:cont_replace] : {/^ZZ+\d+-/ => ''}
      date = options.include?(:date) ? options[:date] : DateTime.now.to_date
      @date = date
      (LOG.fatal "No chapters given!" and return) unless chapter_list
      @errors = []
      
      today_time = DateTime.new(@date.year, @date.month, @date.day, 10, 0, 0)
      
      done = []
      upd_chapter_col = {}
      day_list = [1,2,3,4,5,6,7,-1]
      day_list.each do |days_ago|
        early_time = today_time - days_ago
        late_time = early_time + 1
        
        if days_ago == 2
          if upd_chapter_col[1]
            upd_chapter_col[1].each do |chapter_thing|
              chapter = chapter_thing[:chapter]
              first_update = chapter_thing[:first_update]
              last_update = chapter_thing[:last_update]
              latest_update = chapter_thing[:latest_update]
              
              was_yesterday = false
              messages = [chapter.entry] + chapter.replies
              messages.each do |message|
                was_yesterday = true if message.time.between?(early_time, late_time)
              end
              
              chapter_thing[:yesterday] = was_yesterday
            end
          end
        end
        
        upd_chapters = []
        chapter_list.each do |chapter|
          next if done.include?(chapter)
          next unless chapter.entry
          
          first_update = nil
          last_update = nil
          latest_update = nil
          messages = [chapter.entry] + chapter.replies
          messages.each do |message|
            in_period = (days_ago > 0) ? message.time.between?(early_time, late_time) : false
            first_update = message if in_period and not first_update
            last_update = message if in_period
            latest_update = message if message.time < today_time
          end
          
          if first_update
            upd_chapters << {chapter: chapter, first_update: first_update, last_update: last_update, latest_update: latest_update}
            done << chapter
          end
          if days_ago < 1
            upd_chapters << {chapter: chapter, latest_update: latest_update}
            done << chapter
          end
        end
        
        upd_chapter_col[days_ago] = upd_chapters
      end
      
      day_list.each do |days_ago|
        early_time = today_time - days_ago
        late_time = early_time + 1
        
        upd_chapters = upd_chapter_col[days_ago]
        if days_ago >= 1 and not upd_chapters.empty?
          LOG.info "#{days_ago == 1 ? 'New updates' : 'Last updated'} #{early_time.strftime('%m-%d')}:"
          LOG.info "[list#{days_ago==1 ? '=1' : ''}]"
          if days_ago == 1
            upd_chapters.sort! { |x,y| y[:first_update].time <=> x[:first_update].time }
            first_last = :first
            new_after = early_time
            show_last_author = false
          else
            upd_chapters.sort! { |x,y| y[:last_update].time <=> x[:last_update].time }
            first_last = :last
            new_after = today_time + 3
            show_last_author = :unless_completed
          end
          upd_chapters.each do |chapter_thing|
            LOG.info chapterthing_displaytext(chapter_thing, first_last: first_last, completed_before: late_time, new_after: new_after, show_last_author: show_last_author)
          end
          LOG.info "[/list]"
          
          if days_ago == 1
            dw_upd_chapters = upd_chapters.select {|chapter_thing| GlowficSiteHandlers::DreamwidthHandler.handles?(chapter_thing[:chapter]) }
            if dw_upd_chapters and not dw_upd_chapters.empty?
              LOG.info "[spoiler-box=DW Only]New updates #{early_time.strftime('%m-%d')}:"
              LOG.info "[list]"
              dw_upd_chapters.each do |chapter_thing|
                LOG.info chapterthing_displaytext(chapter_thing, first_last: :first, completed_before: late_time, new_after: early_time)
              end
              LOG.info "[/list][/spoiler-box]"
            end
            
            not_yesterdays = upd_chapters.select {|chapter_thing| chapter_thing[:yesterday] == false}
            if not_yesterdays and not not_yesterdays.empty?
              LOG.info "[spoiler-box=Today, not yesterday]New updates #{early_time.strftime('%m-%d')}:"
              LOG.info "[list]"
              not_yesterdays.each do |chapter_thing|
                LOG.info chapterthing_displaytext(chapter_thing, first_last: :first, completed_before: late_time, new_after: early_time)
              end
              LOG.info "[/list][/spoiler-box]"
            end
            
            sec_upd_chapters = upd_chapters.select {|chapter_thing| chapter_thing[:chapter].sections.present? }
            if sec_upd_chapters.present?
              LOG.info "[spoiler-box=Continuities]New updates #{early_time.strftime('%m-%d')}:"
              LOG.info "[list]"
              sec_upd_chapters.sort! do |chapter_thing1, chapter_thing2|
                sect_diff = chapter_thing1[:chapter].sections.map {|thing| (thing.is_a?(String) ? thing.downcase : thing)} <=> chapter_thing2[:chapter].sections.map {|thing| (thing.is_a?(String) ? thing.downcase : thing)}
                if sect_diff == 0
                  chapter_thing2[:first_update].time <=> chapter_thing1[:first_update].time
                else
                  sect_diff
                end
              end
              sec_upd_chapters.each do |chapter_thing|
                LOG.info chapterthing_displaytext(chapter_thing, first_last: :first, completed_before: late_time, new_after: early_time, show_sections: true)
              end
              LOG.info "[/list][/spoiler-box]"
            end
          end
        elsif show_earlier && !upd_chapters.empty?
          LOG.info "Earlier:"
          LOG.info "[list]"
          upd_chapters.sort! { |x,y| y[:latest_update].time <=> x[:latest_update].time }
          upd_chapters.each do |chapter_thing|
            LOG.info chapterthing_displaytext(chapter_thing, first_last: :latest, completed_before: late_time, new_after: today_time + 3, show_last_update_time: true, show_last_author: :unless_completed)
          end
          LOG.info "[/list]"
        end
      end
      LOG.info "[url=http://alicorn.elcenia.com/board/viewtopic.php?f=10&t=498#p25059]Official moiety list[/url] ([url=http://alicorn.elcenia.com/board/viewtopic.php?f=10&t=498#p25060]rainbow[/url])"
      
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
      @confirm_dupes = (options.key?(:confirm_dupes) ? options[:confirm_dupes] : DEBUGGING)
    end
    
    def character_for_author(author)
      return @char_cache[author.unique_id] if @char_cache.key?(author.unique_id)
      return nil unless author.unique_id
      user = user_for_author(author)
      chars = nil
      author.screenname = author.unique_id.sub('dreamwidth#', '') if !author.screenname.present? && author.unique_id.start_with?('dreamwidth#')
      
      chars = Character.where(user_id: user.id, screenname: author.screenname) if author.screenname.present?
      chars = Character.where(user_id: user.id, name: author.name) if author.name.present? && !chars.present?
      unless chars.present?
        # unique_ids:
        # dreamwidth#{author_id}
        # constellation#user#{user_id}
        # constellation#{character_id}
        skip_creation = false
        if author.unique_id.start_with?('constellation#user#')
          chars = [] # character is nil if it's a user post
          skip_creation = true
        elsif author.unique_id.start_with?('constellation#')
          char_id = author.unique_id.sub('constellation#', '')
          chars = Character.where(user_id: user.id, id: char_id)
        end
        
        unless skip_creation or chars.present?
          char = Character.create!(user: user, name: author.name, screenname: author.screenname)
          LOG.info "- Created character '#{author.name}' for author '#{user.username}'."
        end
      end
      char ||= chars.first
      @char_cache[author.unique_id] = char
      if author.default_face.present?
        default_icon = icon_for_face(author.default_face)
        if char.present? && default_icon.present?
          char.update_attributes(default_icon: default_icon)
          LOG.debug "- Set a default icon for #{char.name}: #{default_icon.id}"
        end
      else
        LOG.warn("- Character has no default face: #{author}")
      end
      char
    end
    def gallery_for_author(author)
      return @gallery_cache[author.unique_id] if @gallery_cache.key?(author.unique_id)
      char = character_for_author(author)
      return nil unless char
      if char.galleries.empty?
        LOG.debug "- Created gallery for #{author.name}"
        char.galleries.build(user: char.user, name: author.name)
        char.save!
      else
        LOG.debug "- #{author.name} has an uncached gallery; using it. (ID #{char.galleries.first.id})"
      end
      @gallery_cache[author.unique_id] = char.galleries.first
    end
    def user_for_author(author, options={})
      return @user_cache[author.unique_id] if @user_cache.key?(author.unique_id)
      return nil unless author.unique_id
      set_coauthors = options.key?(:set_coauthors) ? options[:set_coauthors] : @set_coauthors
      moieties = author.moiety.try(:split, ' ').try(:uniq)
      moieties = ['Unknown Author'] unless moieties.present?
      moiety = moieties.first
      cached_moiety = moieties.find {|moiety_val| @usermoiety_cache.key?(moiety_val) }
      return @usermoiety_cache[cached_moiety] if cached_moiety
      LOG.warn("- Character has many moieties (#{author.moiety})") if moieties.length > 1
      
      users = User.where('lower(username) = ?', moieties.map(&:downcase))
      unless users.present?
        rewrites = moieties.map{|moiety| @user_moiety_rewrite.keys.detect{|key| key.downcase == moiety.downcase} }.compact.map{|key| @user_moiety_rewrite[key].downcase}
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
            user = User.create!(username: moiety, password: moiety.downcase, email: moiety.downcase.gsub(/[^\w\-_\.+]/, '') + '@example.com')
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
      @user_cache[author.unique_id] = user
      @usermoiety_cache[user.try(:username).try(:downcase)] = user
    end
    def icon_for_face(face)
      return nil unless face.present? and face.imageURL.present?
      return @icon_cache[face.unique_id] if @icon_cache.key?(face.unique_id)
      user = user_for_author(face.author)
      gallery = gallery_for_author(face.author)
      icon = Icon.where(url: face.imageURL, user_id: user.id).includes(:galleries).select{|icon| icon.galleries.include?(gallery)}.first
      unless icon.present?
        icon = Icon.where(url: face.imageURL, user_id: user.id).first
        gallery.icons << icon if gallery && icon.present?
      end
      unless icon.present?
        gallery = gallery_for_author(face.author)
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
        first_user = user_for_author(chapter_list.authors.first, set_coauthors: false)
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
      writable.user = user_for_author(message.author)
      writable.character = character_for_author(message.author)
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
      
      Post.record_timestamps = false
      Reply.record_timestamps = false
      chapter_count = chapter_list.count
      chapter_list.each_with_index do |chapter, i|
        (LOG.error "(#{i}/#{chapter_count}) Chapter has no entry: #{chapter}" and next) unless chapter.entry.present?
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
        chapter.replies.each_with_index do |reply, i|
          repl = reply_for_comment(reply, threaded, thread_id, reply == chapter.replies.last)
          thread_id = repl.thread_id if threaded
          if (i+1) % 100 == 0
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
