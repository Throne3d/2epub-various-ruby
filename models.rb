class Object
  def try(*params, &block)
    if params.empty? && block_given?
      yield self
    else
      public_send(*params, &block) if respond_to? params.first
    end
  end
end

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
    def each(&block)
      @chapters.each(&block)
    end
    def to_json(options={})
      hash = {:"@chapters" => @chapters}
      hash.to_json(options)
    end
    def from_json! string
      JSON.parse(string).each do |var, val|
        self.instance_variable_set var, val unless var == "@chapters"
        
        @chapters = []
        val.each do |chapter_hash|
          chapter_hash.keys.each do |key|
            next unless key and not key.empty?
            next unless key.start_with?("@")
            next if key.start_with?("@@")
            next if key.length == 1
            chapter_hash[key[1..-1]] = chapter_hash[key]
            chapter_hash.delete(key)
          end
          chapter = Chapter.new(chapter_hash)
          @chapters << chapter
        end
      end
    end
  end

  class Chapter
    attr_accessor :path, :title, :title_extras, :sections, :thread, :section, :section_extras, :page_count, :entry_title, :entry, :posts, :pages_loaded
    attr_reader :url, :smallURL
    
    def initialize(params={})
      param_transform = {:name => :title, :loaded => :pages_loaded, :name_extras => :title_extras}
      params.keys.each do |param|
        if param.is_a? String
          params[param.to_sym] = params[param]
          params.delete param
          param = param.to_sym
        end
        if param_transform.key?(param)
          params[param_transform[param]] = params[param]
          params.delete param
          param = param_transform[param]
        end
      end
      @smallURL = nil
      @title = nil
      @sections = []
      @thread = nil
      @page_count = 0
      @entry_title = nil
      @entry = nil
      @posts = []
      @pages_loaded = 0
      
      allowed_params = [:path, :title, :title_extras, :thread, :sections, :page_count, :entry_title, :entry, :posts, :pages_loaded, :url]
      params.reject! do |param|
        unless allowed_params.include?(param)
          raise(ArgumentError, "Invalid parameter: #{param} = #{params[param]}") unless serialize_ignore?(param)
          true
        end
      end
      
      raise(ArgumentError, "URL must be given") unless (params.key?(:url) and not params[:url].strip.empty?)
      raise(ArgumentError, "Chapter Title must be given") unless (params.key?(:title) and not params[:title].strip.empty?)
      allowed_params.each do |symbol|
        public_send("#{symbol}=", params[symbol]) if params[symbol]
      end
      self.path=get_page_location(url) unless params.key?(:path)
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
      str = "\"#{title}\""
      str += " #{title_extras}" unless title_extras.nil? or title_extras.empty?
      str += ": #{smallURL}"
    end
    
    def self.serialize_ignore?(thing)
      return false if @serialize_ignore.nil?
      @serialize_ignore.include?(thing) or (thing.is_a? String and @serialize_ignore.include?(thing.to_sym))
    end
    def self.serialize_ignore(*things)
      
      @serialize_ignore = things
    end
    def serialize_ignore?(thing)
      self.class.serialize_ignore?(thing)
    end
    
    serialize_ignore(:smallURL)
    def to_json(options={})
      hash = {}
      self.instance_variables.each do |var|
        var_str = (var.is_a? String) ? var : var.to_s
        var_sym = var_str[1..-1].to_sym if var_str.length > 1 and var_str.start_with?("@") and not var_str.start_with?("@@")
        hash[var_sym] = self.instance_variable_get var unless serialize_ignore?(var_sym)
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
