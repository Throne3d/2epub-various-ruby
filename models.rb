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
  
  MOIETIES = {
    "Adalene" => ["lurkingkobold", "wish-i-may"],
    "Adiva" => ["gothamsheiress", "adivasheadvoices"],
    "Ajzira" => ["lost-in-translation", "hearing-shadows"],
    "AndaisQ" => ["fortheliving", "quite-enchanted", "andomega", "in-like-a", "hemomancer", "white-ram", "power-in-the", "strangely-literal", "sonofsnow", "dontbelieveinfairies"],
    "Anthusiasm" => ["queenoftrash"],
    "armokGoB" => ["armokgob"],
    "Benedict" => ["unblinkered", "penitencelost"],
    "Calima" => ["tenn-ambar-metta"],
    "Ceitfianna" => ["balancingminds", "mm-ceit"],
    "ChristyHotwater" => ["slgemp141"],
    "CuriousDiscoverer" => ["mage-see-mage-do", "abodyinmotion", "superego-medico", "not-without-scars", "breeds-contempt", "curiousdiscoverer", "come-forth-winter", "copycast", "of-all-trades", "ignite-the-light", "there-is-no-such-thing-as", "unadalturedstrength", "tailedmonstrosity", "curiousbox"], #Bluelantern
    "Endovior" => ["withmanyfingers"],
    "ErinFlight" => ["thrown-in", "regards-the-possibilities", "back-from-nowhere", "vive-la-revolution"],
    "Eva" => ["kaolinandbone", "evesystem", "all-the-worlds-have", "walksonmusic", "eternally-aggrieved"], #evenstar?
    "Kel" => ["kelardry", "dotted-lines"], #BlueSkySprite
    "kuuskytkolme" => ["can-i-help", "can-i-stay", "can-i-go"],
    "Link" => ["meletiti-entelecheiai", "chibisilian"], #chibisilian is assumed from "Location: Entelechy"
    "Liz" => ["sun-guided"],
    "Lynette" => ["darkeningofthelight", "princeofsalem"],
    "Maggie" => ["maggie-of-the-owls", "whatamithinking", "iamnotpolaris", "amongstherpeers", "amongstthewinds", "asteptotheright", "jumptotheleft", "themainattraction", "swordofdamocles", "swordofeden", "feyfortune", "mutatis-mutandis", "mindovermagic", "ragexserenity"],
    "Nemo" => ["magnifiedandeducated", "connecticut-yankee", "unprophesied-of-ages", "nemoconsequentiae", "wormcan", "off-to-be-the-wizard", "whole-new-can"],
    "roboticlin" => ["roboticlin"],
    "Rockeye" => ["witchwatcher", "rockeye-stonetoe", "sturdycoldsteel", "characterquarry", "allforthehive", "neuroihive", "smallgod"],
    "Sigma" => ["spiderzone"], #Ezra
    "Teceler" => ["scatteredstars", "onwhatwingswedareaspire"],
    "TheOneButcher" => ["theonebutcher"],
    "Timepoof" => ["timepoof"],
    "Unbitwise" => ["unbitwise", "wind-on-my-face", "synchrosyntheses"],
    "Verdancy" => ["better-living", "forestsofthe"],
    "Yadal" => ["yorisandboxcharacter", "kamikosandboxcharacter"],
    "Zack" => ["intomystudies"]
    #, "Unknown":["ambrovimvor", "hide-and-seek", "antiprojectionist", "vvvvvvibrant", "botanical-engineer", "fine-tuned"]
  }
  
  def self.build_moieties()
    file_path = "collectionPages.txt"
    return MOIETIES unless File.file?(file_path)
    
    open(file_path, 'r') do |file|
      file.each do |line|
        next if line.chomp.strip.empty?
        collection_name = line.chomp.split(" ~#~ ").first
        collection_url = line.chomp.sub("#{collection_name} ~#~ ", "")
        
        collection_data = get_page_data(collection_url, replace: true)
        collection = Nokogiri::HTML(collection_data)
        
        moiety_key = nil
        MOIETIES.keys.each do |key|
          moiety_key = key if key.downcase.strip == collection_name.downcase.strip
        end
        if moiety_key.nil?
          moiety_key = collection_name
          MOIETIES[moiety_key] = []
        end
        
        count = 0
        collection.css('#members_people_body a').each do |user_element|
          MOIETIES[moiety_key] << user_element.text.strip.gsub('_', '-')
          count += 1
        end
        
        LOG.info "Processed collection #{collection_name}: #{count} member#{count==1 ? '' : 's'}."
      end
    end
  end
  
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
      things = things.map do |thing|
        (thing.is_a? String) ? thing.to_sym : thing
      end
      @serialize_ignore = [] unless @serialize_ignore
      things.each {|thing| @serialize_ignore << thing}
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
        var_sym = var_str.to_sym
        var_sym = var_str[1..-1].to_sym if var_str.length > 1 and var_str.start_with?("@") and not var_str.start_with?("@@")
        hash[var_sym] = self.instance_variable_get var unless serialize_ignore?(var_sym)
      end
      hash.to_json(options)
    end
    def from_json! string
      json_hash = if string.is_a? String
        JSON.parse(string)
      elsif string.is_a? Hash
        string
      else
        raise(ArgumentError, "Not a string or a hash.")
      end
      
      json_hash.each do |var, val|
        var = "@#{var}" unless var.to_s.start_with?("@")
        self.instance_variable_set var, val
      end
    end
  end
  
  class Chapters < Model
    attr_reader :chapters, :faces, :authors
    def initialize
      @chapters = []
      @faces = []
      @authors = []
    end
    
    def add_face(arg)
      @faces << arg
    end
    def get_face_by_id(face_id)
      found_face = nil
      @faces.each do |face|
        found_face = face if face.unique_id == face_id
      end
      found_face
    end
    
    def <<(arg)
      if (arg.is_a?(Face))
        self.add_face(arg)
      else
        @chapters << arg
      end
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
      json_hash = if string.is_a? String
        JSON.parse(string)
      elsif string.is_a? Hash
        string
      else
        raise(ArgumentError, "Not a string or a hash.")
      end
        
      json_hash.each do |var, val|
        varname = (var.start_with?("@")) ? var[1..-1] : var
        self.instance_variable_set var, val unless varname == "chapters" or varname == "faces" or varname == "authors"
      end
      
      authors = json_hash["authors"] or json_hash["@authors"]
      faces = json_hash["faces"] or json_hash["@faces"]
      chapters = json_hash["chapters"] or json_hash["@chapters"]
      
      @authors = []
      authors.each do |author_hash|
        author = Author.new
        author.from_json! author_hash
        @authors << author
      end
      
      @faces = []
      faces.each do |face_hash|
        face = Face.new
        face.from_json! face_hash
        @faces << face
      end
      
      @chapters = []
      chapters.each do |chapter_hash|
        chapter_hash["chapter_list"] = self
        chapter = Chapter.new
        chapter.from_json! chapter_hash
        @chapters << chapter
      end
    end
  end

  class Chapter < Model
    attr_accessor :title, :title_extras, :thread, :entry_title, :entry, :pages, :replies, :sections, :authors, :entry
    attr_reader :url, :smallURL
    
    param_transform :name => :title, :name_extras => :title_extras
    serialize_ignore :smallURL, :allowed_params, :site_handler, :chapter_list
    
    def allowed_params
      @allowed_params ||= [:title, :title_extras, :thread, :sections, :entry_title, :entry, :replies, :url, :pages, :authors]
    end
    
    def site_handler
      return @site_handler unless @site_handler.nil?
      @site_handler ||= GlowficSiteHandlers.get_handler_for(self)
    end
    def pages
      @pages ||= []
    end
    def replies
      @replies ||= []
    end
    def sections
      @sections ||= []
    end
    def authors
      @authors ||= []
    end
    
    def chapter_list
      @chapter_list
    end
    
    def initialize(params={})
      return if params.empty?
      params = standardize_params(params)
      
      params.reject! do |param|
        unless allowed_params.include?(param)
          raise(ArgumentError, "Invalid parameter: #{param} = #{params[param]}") unless serialize_ignore?(param)
          true
        end
      end
      
      @pages = []
      @replies = []
      @sections = []
      @authors = []
      
      raise(ArgumentError, "URL must be given") unless (params.key?(:url) and not params[:url].strip.empty?)
      raise(ArgumentError, "Chapter Title must be given") unless (params.key?(:title) and not params[:title].strip.empty?)
      allowed_params.each do |symbol|
        public_send("#{symbol}=", params[symbol]) if params[symbol]
      end
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
    
    def from_json! string
      json_hash = if string.is_a? String
        JSON.parse(string)
      elsif string.is_a? Hash
        string
      else
        raise(ArgumentError, "Not a string or a hash.")
      end
        
      json_hash.each do |var, val|
        varname = (var.start_with?("@")) ? var[1..-1] : var
        var = (var.start_with?("@") ? var : "@#{var}")
        self.instance_variable_set var, val unless varname == "replies" or varname == "entry"
        
        if var["replies"]
          @replies = []
          val.each do |reply_hash|
            reply_hash["post_type"] = PostType::REPLY
            reply_hash["chapter"] = self
            reply = Reply.new
            reply.from_json! reply_hash
            @replies << reply
          end
        elsif var["entry"]
          entry_hash = val
          entry_hash["post_type"] = PostType::ENTRY
          entry_hash["chapter"] = self
          entry = Entry.new
          entry.from_json! entry_hash
          @entry = entry
        end
      end
    end
  end

  class Face < Model
    attr_accessor :user, :imageURL, :moiety, :user_display, :keyword, :unique_id
    serialize_ignore :allowed_params
    
    def allowed_params
      @allowed_params ||= [:user, :imageURL, :moiety, :keyword, :user_display, :unique_id]
    end
    
    def initialize(params={})
      return if params.empty?
      params = standardize_params(params)
      
      params.reject! do |param|
        unless allowed_params.include?(param)
          raise(ArgumentError, "Invalid parameter: #{param} = #{params[param]}") unless serialize_ignore?(param)
          true
        end
      end
      
      raise(ArgumentError, "User must be given") unless (params.key?(:user) and not params[:user].nil?)
      raise(ArgumentError, "Unique ID must be given") unless (params.key?(:unique_id) and not params[:unique_id].nil?)
      allowed_params.each do |symbol|
        public_send("#{symbol}=", params[symbol]) if params[symbol]
      end
    end
    def to_s
      "#{user}:#{keyword}"
    end
  end
  
  module PostType
    ENTRY = 0
    REPLY = 1
  end
  
  class Message < Model #post or entry
    attr_accessor :author, :content, :time, :id, :chapter, :post_type, :depth, :children
     
    def self.message_serialize_ignore
      serialize_ignore :author, :chapter, :parent, :children, :face, :allowed_params, :push_title, :face_id, :post_type
    end
    
    def allowed_params
      @allowed_params ||= [:author, :content, :time, :id, :chapter, :parent, :post_type, :depth, :children, :face_id, :face, :entry_title]
    end
    
    @push_title = false
    def entry_title
      @chapter.entry_title
    end
    def entry_title=(newval)
      return (@chapter.entry_title=newval) if @chapter
      @entry_title = newval
      @push_title = true
    end
    
    def chapter=(newval)
      newval.entry_title=@entry_title if @push_title
      @chapter = newval
    end
    
    def depth
      if @parent and not @depth
        @depth = self.parent.depth + 1
      end
      @depth ||= 0
    end
    def children
      @children ||= []
    end
    
    def parent=(newparent)
      if newparent.is_a?(Array)
        @parent = newparent
      else
        @parent = newparent
        @parent.children << self unless @parent.children.include?(self)
        @depth = @parent.depth + 1
      end
    end
    def parent
      if @parent.is_a?(Array)
        #from JSON
        if @parent.length == 2
          @parent = @chapter.entry
        else
          parent_id = newparent.last
          @chapter.replies.each do |reply|
            @parent = reply if reply.id == parent_id
          end
        end
        @parent.children << self unless @parent.children.include?(self)
        @depth = @parent.depth + 1
      end
      @parent
    end
    
    def site_handler
      @chapter.site_handler
    end
    
    def chapter_list
      chapter.chapter_list if chapter
    end
    
    def face
      return unless @face_id
      @face ||= site_handler.get_face_by_id(@face_id)
      @face ||= chapter_list.get_face_by_id(@face_id) if chapter_list
    end
    def face=(face)
      if (face.is_a?(String))
        @face_id = face
        @face = nil
      elsif (face.is_a?(Face))
        @face_id = face.unique_id
        @face = face
      else
        raise(ArgumentError, "Invalid face type")
      end
    end
    def face_id
      @face_id
    end
    def face_id=(id)
      @face = nil
      @face_id = id
    end
    
    def initialize(params={})
      return if params.empty?
      params = standardize_params(params)
      
      params.reject! do |param|
        unless allowed_params.include?(param)
          raise(ArgumentError, "Invalid parameter: #{param} = #{params[param]}") unless serialize_ignore?(param)
          true
        end
      end
      
      raise(ArgumentError, "Author must be given") unless (params.key?(:author) and not params[:author].nil?)
      raise(ArgumentError, "Content must be given") unless params.key?(:content)
      allowed_params.each do |symbol|
        public_send("#{symbol}=", params[symbol]) if params[symbol]
      end
    end
    def to_s
      if @post_type
        if @post_type == PostType::ENTRY
          "#{community}##{id}"
        elsif @post_type == PostType::REPLY
          "#{community}##{chapter.entry.id}##{id}"
        end
      else
        "#{community}##{id}"
      end
    end
    
    def to_json(options={})
      hash = {}
      self.instance_variables.each do |var|
        var_str = (var.is_a? String) ? var : var.to_s
        var_sym = var_str.to_sym
        var_sym = var_str[1..-1].to_sym if var_str.length > 1 and var_str.start_with?("@") and not var_str.start_with?("@@")
        hash[var_sym] = self.instance_variable_get var unless serialize_ignore?(var_sym)
        
        if var_str == "parent"
          parent = self.instance_variable_get(var)
          hash[var_sym] = [parent.community, parent.chapter.entry.id, parent.id] if parent.post_type == PostType::REPLY
          hash[var_sym] = [parent.community, parent.id] if parent.post_type == PostType::ENTRY
        elsif var_str == "face"
          face = self.instance_variable_get(var)
          hash[var_sym] = face.unique_id
        end
      end
      hash.to_json(options)
    end
  end

  class Reply < Message
    message_serialize_ignore
    def initialize(params={})
      super(params)
      @post_type = PostType::REPLY
    end
  end
  
  class Entry < Message
    message_serialize_ignore
    def initialize(params={})
      super(params)
      @post_type = PostType::ENTRY
    end
  end
  
  class Author < Model
    def initialize
    end
  end
end
