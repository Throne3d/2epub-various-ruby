module GlowficEpub
  require 'model_methods'
  require 'json'
  include GlowficEpubMethods
  
  class Chapters
    attr_reader :chapters
    def initialize
      @chapters = []
    end
    def <<(arg)
      @chapters << arg
    end
    def length
      @chapters.length
    end
    def empty?
      @chapters.empty?
    end
    def each
      @chapters.each
    end
    def to_json(options={})
      hash = {:"@chapters" => @chapters}
      hash.to_json(options)
    end
    def from_json! string
      JSON.parse(string).each do |var, val|
        self.instance_variable_set var, val
      end
    end
  end

  class Chapter
    attr_accessor :path, :name, :name_extras, :sections, :thread, :section, :section_extras, :page_count, :entry_title, :entry, :posts, :fully_loaded
    attr_reader :url, :smallURL
    
    def initialize(params={})
      @smallURL = nil
      @name = nil
      @sections = []
      @thread = nil
      @page_count = 0
      @entry_title = nil
      @entry = nil
      @posts = []
      @fully_loaded = 0
      
      raise(ArgumentError, "URL must be given") unless (params.key?(:url) and not params[:url].strip.empty?)
      raise(ArgumentError, "Chapter Title must be given") unless (params.key?(:name) and not params[:name].strip.empty?)
      [:path, :name, :name_extras, :thread, :sections, :page_count, :entry_title, :entry, :posts, :fully_loaded].each do |symbol|
        public_send("#{symbol}=", params[symbol]) if params[symbol]
      end
      self.url=params[:url]
      self.path=get_page_location(url)
    end
    def url=(newURL)
      @url=newURL
      @smallURL=Chapter.shortenURL(@url)
    end
    def self.shortenURL(longURL)
      uri = URI.parse(longURL)
      if uri.query and not uri.query.empty?
        query = CGI.parse(uri.query)
        query.delete("style")
        query.delete("view")
        query = URI.encode_www_form(query)
        uri.query = (query.empty?) ? nil : query
      end
      uri.host = uri.host.sub(/\.dreamwidth\.org$/, ".dreamwidth")
      uri.to_s.sub(/^https?\:\/\//, "").sub(/\.html$/, "")
    end
    def to_s
      str = "\"#{name}"
      str += " #{name_extras}" unless name_extras.nil? or name_extras.empty?
      str += "\": #{smallURL}"
    end
    
    def to_json(options={})
      hash = {}
      self.instance_variables.each do |var|
        hash[var] = self.instance_variable_get var
      end
      hash.to_json(options)
    end
    def from_json! string
      JSON.parse(string).each do |var, val|
        self.instance_variable_set var, val
      end
    end
  end

  class Face
    attr_accessor :user, :imageURL, :moiety, :imagePath, :face, :userDisplay
    def initialize
      @user = nil
      @imageURL = nil
      @moiety = nil
      @imagePath = nil
      @face = nil
      @userDisplay = nil
    end
    def to_s
      "#{user}:#{face}"
    end
    
    def to_json(options={})
      hash = {}
      self.instance_variables.each do |var|
        hash[var] = self.instance_variable_get var
      end
      hash.to_json(options)
    end
    def from_json! string
      JSON.parse(string).each do |var, val|
        self.instance_variable_set var, val
      end
    end
  end

  class Post #post or comment
    attr_accessor :author, :content, :time, :id, :chapter, :depth, :parent, :postTitle, :postType, :children
    def initialize
      @author = nil
      @content = nil
      @time = nil
      @id = nil
      @chapter = nil
      @depth = 0
      @parent = nil
      @postTitle = nil
      @postType = nil
      @children = []
      @community = nil
    end
    def to_s
      "#{community}##{id}"
    end
    
    def to_json(options={})
      hash = {}
      self.instance_variables.each do |var|
        hash[var] = self.instance_variable_get var
      end
      hash.to_json(options)
    end
    def from_json! string
      JSON.parse(string).each do |var, val|
        self.instance_variable_set var, val
      end
    end
  end
end
