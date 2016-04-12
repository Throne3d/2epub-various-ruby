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
      FileUtils::mkdir_p "output/epub/#{@group}/style/"
      FileUtils::mkdir_p "output/epub/#{@group}/html/"
      FileUtils::mkdir_p "output/epub/#{@group}/images/"
      @face_path_cache = {}
    end
    
    def get_face_path(face)
      face_url = face if face.is_a?(String)
      face_url = face.imageURL if face.is_a?(Face)
      return "" if face_url.nil? or face_url.empty?
      return @face_path_cache[face_url] if @face_path_cache.key?(face_url)
      
      uri = URI.parse(face_url)
      save_path = "output/epub/#{@group}"
      uri_path = uri.path
      uri_path = uri_path[1..-1] if uri_path.start_with?("/")
      relative_file = File.join(uri.host, uri_path.gsub('/', '-'))
      download_file(face_url, save_path: File.join(save_path, "images", relative_file), replace: false)
      
      @files << {File.join(save_path, "images", relative_file) => File.join("EPUB", "images", File.dirname(relative_file))}
      @face_path_cache[face_url] = File.join("..", "images", relative_file)
    end
    
    def get_chapter_path(options = {})
      chapter_url = options[:chapter].url if options.key?(:chapter)
      chapter_url = options[:chapter_url] if options.key?(:chapter_url)
      group = options.key?(:group) ? options[:group] : @group
      
      uri = URI.parse(chapter_url)
      save_path = "output/epub/#{group}"
      save_file = uri.host.sub(".dreamwidth.org", "").sub("vast-journey-9935.herokuapp.com", "constellation")
      uri_path = uri.path
      uri_path = uri_path[1..-1] if uri_path.start_with?("/")
      save_file += "-" + uri_path.sub(".html", "") + ".html"
      save_path = File.join(save_path, "html", save_file.gsub("/", "-"))
    end
    
    def get_relative_chapter_path(options = {})
      chapter_url = options[:chapter].url if options.key?(:chapter)
      chapter_url = options[:chapter_url] if options.key?(:chapter_url)
      
      uri = URI.parse(chapter_url)
      save_file = uri.host.sub(".dreamwidth.org", "").sub("vast-journey-9935.herokuapp.com", "constellation")
      uri_path = uri.path
      uri_path = uri_path[1..-1] if uri_path.start_with?("/")
      save_file += "-" + uri_path.sub(".html", "") + ".html"
      save_path = save_file.gsub("/", "-")
      File.join("EPUB", "html", save_path)
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
      
      template_chapter = ""
      open("template_chapter.erb") do |file|
        template_chapter = file.read
      end
      template_message = ""
      open("template_message.erb") do |file|
        template_message = file.read
      end
      
      style_path = "output/epub/#{@group}/style/default.css"
      open("style.css", 'r') do |style|
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
      
      @files = [{style_path => "EPUB/style"}]
      
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
          next unless img_src.start_with?("http://") or img_src.start_with?("https://")
          img_element["src"] = get_face_path(img_src)
        end
        
        open(save_path, 'w') do |file|
          file.write page.to_s
        end
        @files << {save_path => File.dirname(get_relative_chapter_path(chapter: chapter))}
        LOG.info "Did chapter #{chapter}"
      end
      
      @files.each do |thing|
        thing.keys.each do |key|
          next if key.start_with?("/")
          thing[File.join(Dir.pwd, key)] = thing[key]
          thing.delete(key)
        end
      end
      
      files_list = @files
      group_name = @group
      epub_path = "output/epub/#{@group}.epub"
      epub = EeePub.make do
        title "#{group_name}"
        creator FIC_AUTHORSTRINGS[group_name]
        publisher ''
        date DateTime.now.strftime("%Y-%m-%d")
        identifier FIC_TOCS[group_name], scheme: 'URL'
        uid "glowfic-#{group_name}"
        
        files files_list
        nav nav_array
      end
      epub.save(epub_path)
    end
  end
end
