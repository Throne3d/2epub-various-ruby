﻿module GlowficSiteHandlers
  require 'model_methods'
  require 'models'
  require 'uri'
  include GlowficEpubMethods
  
  class SiteHandler
    def self.handles?(chapter)
      false
    end
  end
  
  class DreamwidthHandler < SiteHandler
    def self.handles?(chapter)
      return false if not chapter.url or chapter.url.empty?
      
      uri = URI.parse(chapter.url)
      return uri.host.end_with?("dreamwidth.org")
    end
    def initialize(options = {})
      @group = nil
      @group = options[:group] if options.key?(:group)
    end
  end
end