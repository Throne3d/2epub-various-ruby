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
  
  class Model
    def initialize
      @param_transform = {}
      @serialize_ignore = []
    end
    def standardize_params(params = {})
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
        params.delete param if params[param].nil?
      end
      params
    end
    def self.serialize_ignore? thing
      return false if @serialize_ignore.nil?
      thing = thing.to_sym if thing.is_a? String
      @serialize_ignore.include? thing
    end
    def self.serialize_ignore(*things)
      things = things.first if things.length == 1 and things.first.is_a? Array
      @serialize_ignore = things.map do |thing|
        (thing.is_a? String) ? thing.to_sym : thing
      end
    end
    def serialize_ignore?(thing)
      self.class.serialize_ignore?(thing)
    end
    
    def self.param_transform(**things)
      if things.length == 0
        return @param_transform || {}
      end
      things.keys.each do |param|
        if param.is_a? String
          things[param.to_sym] = things[param]
          things.delete param
          param = param.to_sym
        end
        if things[param].is_a? String
          things[param] = things[param].to_sym
        end
      end
      @param_transform = things
    end
    def param_transform
      self.class.param_transform
    end
    
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
  
  class Chapters < Model
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
    def from_json! string
      JSON.parse(string).each do |var, val|
        self.instance_variable_set var, val unless var == "@chapters" or var == "chapters"
        
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

  class Chapter < Model
    attr_accessor :path, :title, :title_extras, :thread, :entry_title, :entry, :pages, :posts, :sections
    attr_reader :url, :smallURL
    
    param_transform :name => :title, :name_extras => :title_extras
    serialize_ignore :smallURL, :allowed_params
    
    def allowed_params
      @allowed_params ||= [:path, :title, :title_extras, :thread, :sections, :entry_title, :entry, :posts, :url, :pages]
    end
    
    def pages
      @pages ||= []
    end
    def posts
      @posts ||= []
    end
    def sections
      @sections ||= []
    end
    
    def initialize(params={})
      params = standardize_params(params)
      
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
  end

  class Face < Model
    attr_accessor :user, :imageURL, :moiety, :image_path, :face, :user_display
    
    def allowed_params
      @allowed_params ||= [:user, :imageURL, :moiety, :image_path, :face, :user_display]
    end
    
    def initialize
    end
    def to_s
      "#{user}:#{face}"
    end
  end

  class Post < Model #post or comment
    attr_accessor :author, :content, :time, :id, :chapter, :parent, :post_title, :post_type, :depth, :children
    
    def allowed_params
      @allowed_params ||= [:author, :content, :time, :id, :chapter, :parent, :post_title, :post_type]
    end
    
    def depth
      @depth ||= 0
    end
    def children
      @children ||= []
    end
    
    def initialize
    end
    def to_s
      "#{community}##{id}"
    end
  end
end
