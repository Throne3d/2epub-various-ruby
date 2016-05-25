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
      @group_folder = File.join('output', 'epub', @group)
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
      test_ext = "" if test_ext == filename
      test_ext = "." + test_ext if test_ext and not test_ext.empty?
      test_filename = filename.sub("#{test_ext}", "")
      i = 0
      relative_file = sanitize_local_path(File.join('images', uri.host, test_filename + test_ext))
      while @paths_used.include?(relative_file)
        i += 1
        temp_filename = "#{test_filename}_#{i}"
        relative_file = sanitize_local_path(File.join('images', uri.host, temp_filename + test_ext))
        LOG.debug "There was an issue with the previous file. Trying alternate path: #{temp_filename + test_ext}"
      end
      @paths_used << relative_file
      download_file(face_url, save_path: File.join(save_path, relative_file), replace: false)
      
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
      
      nav_array = navify_navbits(nav_bits)
      
      @files = [{style_path => 'EPUB/style'}]
      
      @show_authors = FIC_SHOW_AUTHORS.include?(@group)
      
      chapter_list.each do |chapter|
        @chapter = chapter
        #messages = [@chapter.entry] + @chapter.replies
        #messages.reject! {|element| element.nil? }
        (LOG.error "No entry for chapter." and next) unless chapter.entry
        (LOG.info "Chapter is entry-only.") if chapter.replies.nil? or chapter.replies.empty?
        
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
        
        save_path = get_chapter_path(chapter: chapter, group: @group)
        
        page = Nokogiri::HTML(page_data)
        page.css('img').each do |img_element|
          img_src = img_element.try(:[], :src)
          next unless img_src
          next unless img_src.start_with?('http://') or img_src.start_with?('https://')
          img_element[:src] = get_face_path(img_src)
        end
        
        open(save_path, 'w') do |file|
          file.write page.to_s
        end
        @files << {save_path => File.dirname(get_relative_chapter_path(chapter: chapter))}
        LOG.info "Did chapter #{chapter}"
      end
      
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
end
