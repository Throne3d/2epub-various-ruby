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
    end
    def get_face_path(face)
      return "" if face.imageURL.nil? or face.imageURL.empty?
      download_file(face.imageURL, where: "output/epub/#{@group}")
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
        
        open(get_page_location(chapter.smallURL, "output/epub/#{@group}"), 'w') do |file|
          file.write page_data
        end
        LOG.info "Did chapter #{chapter}."
      end
    end
  end
end
