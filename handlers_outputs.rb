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
    end
  end
  
  class EpubHandler < OutputHandler
    include ERB::Util
    def initialize(options={})
      super options
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
        @messages = [chapter.entry] + chapter.replies
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
        puts erb.result b
      end
    end
  end
end