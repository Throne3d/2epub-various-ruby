module GlowficOutputHandlers
  require 'model_methods'
  require 'models'
  require 'uri'
  require 'erb'
  include GlowficEpubMethods
  include GlowficEpub::PostType
  
  class OutputHandler
    include GlowficEpub
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
      FileUtils::mkdir_p "output/epub/style/"
      @face_path_cache = {}
    end
    
    def get_face_path(face)
      return "" if face.imageURL.nil? or face.imageURL.empty?
      return @face_path_cache[face.imageURL] if @face_path_cache.key?(face.imageURL)
      
      uri = URI.parse(face.imageURL)
      save_path = "output/epub/#{@group}"
      uri_path = uri.path
      uri_path = uri_path[1..-1] if uri_path.start_with?("/")
      relative_file = File.join(uri.host, uri_path.gsub('/', '-'))
      download_file(face.imageURL, save_path: File.join(save_path, relative_file), replace: false)
      
      @face_path_cache[face.imageURL] = relative_file
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
      save_path = File.join(save_path, save_file.gsub("/", "-"))
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
      template_index = ""
      open("template_index.erb") do |file|
        template_index = file.read
      end
      
      open("style.css", 'r') do |style|
        open("output/epub/style/default.css", 'w') do |css|
          css.write style.read
        end
      end
      
      @toc_html = ""
      toc = []
      sections = []
      chapter_list.each do |chapter|
        num_same = 0
        sections.each_with_index do |section, i|
          if chapter.sections.length <= i
            num_same = chapter.sections.length
            break
          end
          if chapter.sections[i] != section
            num_same = i
            break
          end
          num_same = i + 1
        end
        
        if sections.length > num_same
          ((sections.length-1).downto(num_same)).each do |i|
            @toc_html += "</ol></li>"
          end
          sections = sections.take(num_same)
        end
        
        if chapter.sections.length > sections.length
          ((sections.length).upto(chapter.sections.length-1)).each do |i|
            @toc_html += "<li>" + chapter.sections[i].gsub('<', '&lt;').gsub('>', '&gt;') + "<ol>"
            sections[i] = chapter.sections[i]
          end
        end
        
        @toc_html += "<li><a href=\"" + get_relative_chapter_path(chapter: chapter) + "\">"
        @toc_html += chapter.title.gsub('<', '&lt;').gsub('>', '&gt;') + "</a></li>"
      end
      
      if sections.length > 0
        ((sections.length-1).downto(0)).each do |i|
          @toc_html += "</ol></li>"
        end
      end
      
      @chapter_list = chapter_list
      @sections = []
      erb = ERB.new(template_index, 0, '-')
      b = binding
      index_data = erb.result b
      
      index_path = "output/epub/#{@group}/index.html"
      open(index_path, 'w') do |index_file|
        index_file.write index_data
      end
      
      chapter_list.each do |chapter|
        @chapter = chapter
        @messages = [@chapter.entry] + @chapter.replies
        @messages.reject! {|element| element.nil? }
        (LOG.error "No messages for chapter." and next) if @messages.empty?
        
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
        LOG.info "Did chapter #{chapter}."
      end
    end
  end
end
