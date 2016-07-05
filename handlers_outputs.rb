module GlowficOutputHandlers
  require 'model_methods'
  require 'models'
  require 'uri'
  require 'erb'
  require 'eeepub'
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
      @group_folder = File.join('output', 'epub', @group.to_s)
      @style_folder = File.join(@group_folder, 'style')
      @html_folder = File.join(@group_folder, 'html')
      @images_folder = File.join(@group_folder, 'images')
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
    
    def get_chapter_path(options = {})
      chapter_url = options[:chapter].url if options.key?(:chapter)
      chapter_url = options[:chapter_url] if options.key?(:chapter_url)
      group = options.key?(:group) ? options[:group] : @group
      
      save_path = File.join(@html_folder, get_chapter_path_bit(options))
    end
    
    def get_relative_chapter_path(options = {})
      chapter_url = options[:chapter].url if options.key?(:chapter)
      chapter_url = options[:chapter_url] if options.key?(:chapter_url)
      
      File.join('EPUB', 'html', get_chapter_path_bit(options))
    end
    
    def get_chapter_path_bit(options = {})
      chapter_url = options[:chapter].url if options.key?(:chapter)
      chapter_url = options[:chapter_url] if options.key?(:chapter_url)
      
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
    
    def navify_navbits(navbits, options = {})
      contents_allowed = (options.key?(:contents_allowed) ? options[:contents_allowed] : [])
      navified = []
      if navbits.key?(:_order)
        navbits[:_order].each do |section_name|
          thing = {label: section_name}
          thing[:nav] = navify_navbits(navbits[section_name], options)
          navified << thing
        end
      end
      if navbits.key?(:_contents)
        navbits[:_contents].each do |thing|
          (LOG.info "Ignoring NAV thing: #{thing.inspect}" and next) unless contents_allowed.empty? or contents_allowed.include?(thing[:content])
          navified << thing
        end
      end
      navified
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
      
      nav_bits = {}
      chapter_list.each do |chapter|
        prev_bit = nav_bits
        chapter.sections.each do |section|
          prev_bit[:_order] = [] unless prev_bit.key?(:_order)
          prev_bit[:_order] << section unless prev_bit[:_order].include?(section)
          prev_bit[section] = {} unless prev_bit.key?(section)
          prev_bit = prev_bit[section]
        end
        prev_bit[:_contents] = [] unless prev_bit.key?(:_contents)
        prev_bit[:_contents] << {label: chapter.title, content: get_relative_chapter_path(chapter: chapter)}
      end
      
      @files = [{style_path => 'EPUB/style'}]
      
      @show_authors = FIC_SHOW_AUTHORS.include?(@group)
      
      @save_paths_used = []
      @rel_paths_used = []
      chapter_list.each do |chapter|
        @chapter = chapter
        #messages = [@chapter.entry] + @chapter.replies
        #messages.reject! {|element| element.nil? }
        (LOG.error "No entry for chapter." and next) unless chapter.entry
        (LOG.info "Chapter is entry-only.") if chapter.replies.nil? or chapter.replies.empty?
        save_path = get_chapter_path(chapter: chapter, group: @group)
        (LOG.info "Duplicate chapter not added again" and next) if @save_paths_used.include?(save_path)
        rel_path = get_relative_chapter_path(chapter: chapter)
        
        @messages = []
        message = @chapter.entry
        while message
          @messages << message unless @messages.include?(message)
          new_msg = nil
          
          message.children.each do |child|
            next if @messages.include?(child)
            new_msg = child
            break
          end
          unless new_msg
            new_msg = message.parent
          end
          
          message = new_msg
        end
        
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
        
        open(save_path, 'w') do |file|
          file.write page.to_xhtml(indent_text: '', encoding: 'UTF-8')
        end
        @files << {save_path => File.dirname(rel_path)}
        @save_paths_used << save_path
        @rel_paths_used << rel_path
        LOG.info "Did chapter #{chapter}"
      end
      
      nav_array = navify_navbits(nav_bits, contents_allowed: @rel_paths_used)
      
      @files.each do |thing|
        thing.keys.each do |key|
          next if key.start_with?('/')
          thing[File.join(Dir.pwd, key)] = thing[key]
          thing.delete(key)
        end
      end
      
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
      
      if chapter.report_flags
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
      end
      
      if chapter.title_extras.present? and not chapter.report_flags.present?
        chapter.report_flags = chapter.title_extras.scan(@flag_scan).map{|thing| thing[0] }.uniq.sort{|thing1, thing2| rainbow_comp(thing1, thing2) }.join(' ').strip.gsub(/[\(\)]/, '')
        chapter.title_extras = chapter.title_extras.gsub(@flag_scan, '')
      end
      
      chapter.report_flags = "" unless chapter.report_flags
      
      show_last_author = false unless latest_update.author_str
      
      @errors << "#{chapter}: both completed and hiatused" if completed and hiatus
      
      str = "[*]"
      str << '[size=85]' + chapter.report_flags.strip + '[/size] ' if chapter.report_flags and not chapter.report_flags.strip.empty?
      str << "[url=#{url_thing.permalink}]" if url_thing
      str << '[color=#9A534D]' if hiatus
      str << '[color=goldenrod]' if completed
      str << "#{chapter.entry_title}"
      str << '[/color]' if completed
      str << '[/color]' if hiatus
      str << '[/url]' if url_thing
      str << ' (' + chapter.sections * '>' + ')' if show_sections and chapter.sections.present?
      str << ',' unless chapter.entry_title and chapter.entry_title[/[?,.!;]$/] #ends with ? or , or . or ! or ;
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
      chapter_list = options.include?(:chapter_list) ? options[:chapter_list] : (@chapters ? @chapters : nil)
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
            show_last_author = true
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
        elsif not upd_chapters.empty?
          LOG.info "Earlier:"
          LOG.info "[list]"
          upd_chapters.sort! { |x,y| y[:latest_update].time <=> x[:latest_update].time }
          upd_chapters.each do |chapter_thing|
            LOG.info chapterthing_displaytext(chapter_thing, first_last: :latest, completed_before: late_time, new_after: today_time + 3, show_last_update_time: true, show_last_author: true)
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
end
