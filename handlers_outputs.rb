module GlowficOutputHandlers
  require 'model_methods'
  require 'models'
  require 'uri'
  include GlowficEpubMethods
  include GlowficEpub::PostType
  include ERB::Util
  
  class OutputHandler
    include GlowficEpub
    def initialize(options={})
      @chapters = options[:chapters] if options.key?(:chapters)
      @chapters = options[:chapter_list] if options.key?(:chapter_list)
    end
  end
  
  class EpubHandler < OutputHandler
    def initialize(options={})
      super options
    end
    def output(chapter_list=nil)
      chapter_list = @chapters if chapter_list.nil? and @chapters
      (LOG.fatal "No chapters given!" and return) unless chapter_list
      
      
    end
  end
end