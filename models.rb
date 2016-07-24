module GlowficEpub
  require 'model_methods'
  require 'json'
  require 'date'
  include GlowficEpubMethods
  
  def self.built_moieties?
    @built_moieties ||= false
  end
  def self.built_moieties=(val)
    @built_moieties = val
  end
  def self.build_moieties()
    return @moieties if self.built_moieties?
    
    url = MOIETY_LIST_URL
    file_data = get_page_data(url, where: 'temp', replace: true).strip
    @moieties = JSON.parse(file_data)
    @moieties ||= {}
    
    url = COLLECTION_LIST_URL
    file_data = get_page_data(url, where: 'temp', replace: true).strip
    file_data.split(/\r?\n/).each do |line|
      line = line.strip
      next if line.empty?
      collection_name = line.split(" ~#~ ").first.strip
      collection_url = line.sub("#{collection_name} ~#~ ", "").strip
      
      uri = URI.parse(collection_url)
      collection_id = uri.host.sub(".dreamwidth.org", "")
      
      collection_data = get_page_data(collection_url, replace: true)
      collection = Nokogiri::HTML(collection_data)
      
      moiety_key = nil
      @moieties.keys.each do |key|
        moiety_key = key if key.downcase.strip == collection_name.downcase.strip
      end
      if moiety_key.nil?
        moiety_key = collection_name
        @moieties[moiety_key] = []
      end
      
      @moieties[moiety_key] << collection_id
      count = 0
      collection.css('#members_people_body a').each do |user_element|
        @moieties[moiety_key] << user_element.text.strip.gsub('_', '-')
        count += 1
      end
      
      LOG.info "Processed collection #{collection_name}: #{count} member#{count==1 ? '' : 's'}."
    end
    self.built_moieties=true
  end
  
  def self.moieties
    build_moieties unless self.built_moieties?
    @moieties
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
      return false unless thing.is_a?(String) or thing.is_a?(Symbol)
      thing = thing.to_sym if thing.is_a? String
      @serialize_ignore.include? thing
    end
    def self.serialize_ignore(*things)
      return @serialize_ignore if things.length == 0
      self.serialize_ignore!(*things)
    end
    def serialize_ignore
      @serialize_ignore
    end
    def self.serialize_ignore!(*things)
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
      as_json.to_json(options)
    end
    def as_json(options={})
      hash = {}
      self.instance_variables.each do |var|
        var_str = (var.is_a? String) ? var : var.to_s
        if var_str[0] == '@' and var_str[1] != '@'
          var_str = var_str[1..-1]
          var_sym = var_str.to_sym
        elsif var.is_a?(Symbol)
          var_sym = var
        else
          var_sym = var_str.to_sym
        end
        hash[var_sym] = self.instance_variable_get var unless serialize_ignore?(var_sym)
      end
      hash
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
        var = var.to_s unless var.is_a?(String)
        self.instance_variable_set('@'+var, val)
      end
    end
  end
  
  class Chapters < Model
    attr_reader :chapters, :faces, :authors, :group, :trash_messages
    attr_accessor :group, :old_authors, :old_faces, :sort_chapters
    serialize_ignore :site_handlers, :trash_messages, :old_authors, :old_faces, :kept_authors, :kept_faces, :failed_authors, :failed_faces, :unpacked
    def initialize(options = {})
      @chapters = []
      @faces = []
      @authors = []
      @group = (options.key?(:group)) ? options[:group] : nil
      @sort_chapters = (options.key?(:sort_chapters) ? options[:sort_chapters] : (options.key?(:sort) ? options[:sort] : false))
      @trash_messages = (options.key?(:trash_messages)) ? options[:trash_messages] : false
      @unpacked = false
    end
    
    def site_handlers
      @site_handlers ||= {}
    end
    
    def unpack!
      was_unpacked = @unpacked
      @unpacked = true
      each {|chapter| chapter.unpack! } unless was_unpacked
    end
    def unpacked?
      @unpacked ||= false
    end
    
    def add_author(arg)
      authors << arg unless authors.include?(arg)
    end
    def replace_author(arg)
      return arg if authors.include?(arg)
      authors.delete_if { |author| author.unique_id == arg.unique_id }
      add_author(arg)
      arg
    end
    def get_author_by_id(author_id)
      found_author = authors.find {|author| author.unique_id == author_id}
      if old_authors.present? and not found_author.present?
        found_author = old_authors.find {|author| author.unique_id == author_id}
        add_author(found_author) if found_author
      end
      unless found_author.present?
        LOG.debug "chapterlist(#{self}).get_author_by_id(#{author_id.inspect}) ⇒ not present"
        LOG.debug "authors.length == #{authors.length}; " + (old_authors.present? ? "old_authors.length == #{old_authors.length}" : "No old authors")
      end
      found_author
    end
    def keep_old_author(author_id)
      return nil unless old_authors.present?
      @kept_authors ||= []
      @failed_authors ||= []
      return get_author_by_id(author_id) if @kept_authors.include?(author_id)
      return if @failed_authors.include?(author_id)
      found_author = old_authors.find {|author| author.unique_id == author_id}
      if found_author.present?
        add_author(found_author)
        @kept_authors << author_id
      else
        LOG.error "Failed to find an old author for ID #{author_id}"
        @failed_authors << author_id
      end
      found_author
    end
    def add_face(arg)
      faces << arg unless faces.include?(arg)
    end
    def replace_face(arg)
      return arg if faces.include?(arg)
      faces.delete_if { |face| face.unique_id == arg.unique_id }
      add_face(arg)
      arg
    end
    def get_face_by_id(face_id)
      found_face = faces.find {|face| face.unique_id == face_id}
      if old_faces.present? and not found_face
        old_faces.find {|face| face.unique_id == face_id}
        add_face(found_face) if found_face
      end
      found_face
    end
    def keep_old_face(face_id)
      return nil unless old_faces.present?
      @kept_faces ||= []
      @failed_faces ||= []
      return get_face_by_id(face_id) if @kept_faces.include?(face_id)
      return if @failed_faces.include?(face_id)
      found_face = old_faces.find {|face| face.unique_id == face_id}
      if found_face.present?
        add_face(found_face)
        @kept_faces << face_id
      else
        LOG.error "Failed to find an old face for ID #{face_id}"
        @failed_faces << face_id
      end
      found_face
    end
    
    def add_chapter(arg)
      chapters << arg unless chapters.include?(arg)
      arg.chapter_list = self unless arg.chapter_list == self
      if sort_chapters
        sort_chapters!
      end
    end
    
    def sort_chapters!
      #TODO: do better
      chapters.sort! do |chapter1, chapter2|
        sections1 = if chapter1.sections.present?
          chapter1.sections.map {|thing| thing.downcase}
        else
          []
        end
        sections2 = if chapter2.sections.present?
          chapter2.sections.map {|thing| thing.downcase}
        else
          []
        end
        sections1 <=> sections2
      end
    end
    
    def <<(arg)
      if (arg.is_a?(Face))
        self.add_face(arg)
      elsif (arg.is_a?(Author))
        self.add_author(arg)
      else
        self.add_chapter(arg)
      end
    end
    def length
      chapters.length
    end
    def count
      chapters.count
    end
    def empty?
      chapters.empty?
    end
    def map(&block)
      chapters.map(&block)
    end
    def each(&block)
      chapters.each(&block)
    end
    def each_with_index(&block)
      chapters.each_with_index(&block)
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
        var = var.to_s unless var.is_a?(String)
        self.instance_variable_set('@'+var, val)
      end
      
      LOG.debug "Chapters.from_json! (group: #{group})"
      
      authors = json_hash['authors']
      faces = json_hash['faces']
      chapters = json_hash['chapters']
      
      @authors = []
      @faces = []
      unless trash_messages
        authors.each do |author_hash|
          author_hash['chapter_list'] = self
          author = Author.new
          author.from_json! author_hash
          add_author(author)
        end
        
        faces.each do |face_hash|
          face_hash['chapter_list'] = self
          face = Face.new
          face.from_json! face_hash
          add_face(face)
        end
      end
      
      @chapters = []
      chapters.each do |chapter_hash|
        chapter_hash['chapter_list'] = self
        chapter = Chapter.new(trash_messages: trash_messages)
        chapter.from_json! chapter_hash
        @chapters << chapter
      end
    end
  end

  class Chapter < Model
    attr_accessor :title, :title_extras, :thread, :entry_title, :pages, :check_pages, :replies, :sections, :authors, :url, :report_flags, :processed, :report_flags_processed, :chapter_list, :processed_epub
    attr_reader :entry
    
    param_transform :name => :title, :name_extras => :title_extras
    serialize_ignore :allowed_params, :site_handler, :chapter_list, :trash_messages, :authors, :moieties, :smallURL, :report_flags_processed
    
    def allowed_params
      @allowed_params ||= [:title, :title_extras, :thread, :sections, :entry_title, :entry, :replies, :url, :pages, :check_pages, :authors, :time_completed, :time_hiatus, :report_flags, :processed, :processed_epub]
    end
    
    def unpack!
      entry.unpack! if entry
      replies.each {|reply| reply.unpack! } if replies
    end
    
    def entry_title
      @entry_title || @title
    end
    
    def processed
      processed?
    end
    def processed=(val)
      @processed_epub = false
      @processed=val
    end
    def processed?
     @processed ||= false
    end
    
    def processed_epub
      processed_epub?
    end
    def processed_epub?
      @processed_epub ||= false
    end
    
    def report_flags_processed?
      report_flags_processed
    end
    
    def group
      @chapter_list.group
    end
    def site_handler
      return @site_handler unless @site_handler.nil?
      handler_type = GlowficSiteHandlers.get_handler_for(self)
      chapter_list.site_handlers[handler_type] ||= handler_type.new(group: group, chapters: chapter_list)
      @site_handler ||= chapter_list.site_handlers[handler_type]
    end
    def pages
      @pages ||= []
    end
    def check_pages
      @check_pages ||= []
      if @check_pages.empty? and not self.pages.empty?
        if self.url[/\.dreamwidth\.org/]
          if self.pages.length > 1
            [self.pages.last, self.pages.first]
          else
            self.pages
          end
        elsif self.url['vast-journey-9935.herokuapp.com']
          [set_url_params(clear_url_params(self.url), {page: :last, per_page: 25})]
        else
          self.pages
        end
      else
        @check_pages
      end
    end
    def replies
      @replies ||= []
    end
    def replies=(newval)
      @replies=newval
      @replies.each do |reply|
        reply.chapter = self
      end
      @replies
    end
    def entry=(newval)
      @entry=newval
      @entry.chapter = self
      @entry
    end
    def sections
      if @sections.is_a?(String)
        @sections = [@sections]
      end
      @sections ||= []
    end
    def authors
      @authors ||= []
      if @authors.present? and @authors.select{|thing| thing.is_a?(String)}.present?
        premap = @authors
        @authors = @authors.map {|author| (author.is_a?(String) ? chapter_list.get_author_by_id(author) : author)}
        if @authors.select{|thing| thing.nil?}.present?
          LOG.error "#{self} has a nil author post-mapping.\n#{premap * ', '}\n⇒ #{@authors * ', '}"
        end
      end
      @authors
    end
    
    def chapter_list=(newval)
      @chapter_list=newval
      replies.each do |reply|
        reply.keep_old_stuff
      end
      entry.keep_old_stuff
      newval
    end
    
    def time_completed
      if @time_completed.is_a?(String)
        @time_completed = DateTime.parse(@time_completed)
      elsif @time_completed.is_a?(Date)
        @time_completed = @time_completed.to_datetime
      else
        @time_completed
      end
    end
    def time_completed=(val)
      if val.is_a?(String)
        @time_completed = DateTime.parse(val)
      elsif val.is_a?(Date)
        @time_completed = val.to_datetime
      else
        @time_completed = val
      end
    end
    
    def time_hiatus
      if @time_hiatus.is_a?(String)
        @time_hiatus = DateTime.parse(@time_hiatus)
      elsif @time_hiatus.is_a?(Date)
        @time_hiatus = @time_hiatus.to_datetime
      else
        @time_hiatus
      end
    end
    def time_hiatus=(val)
      if val.is_a?(String)
        @time_hiatus = DateTime.parse(val)
      elsif val.is_a?(Date)
        @time_hiatus = val.to_datetime
      else
        @time_hiatus = val
      end
    end
    
    def moieties
      @moieties if @moieties and not @moieties.empty?
      @moieties = []
      authors.each do |author|
        (LOG.error "nil author for #{self}" and next) unless author
        author.moiety.split(' ').each do |moiety|
          @moieties << moiety unless @moieties.include?(moiety)
        end
      end
      @moieties.sort!
      @moieties
    end
    
    def add_author(newauthor)
      unless newauthor
        LOG.error "add_author(nil) for #{self}"
        puts caller
        return
      end
      same_id = authors.detect{|author| (author.is_a?(Author) ? author.unique_id : author) == (newauthor.is_a?(Author) ? newauthor.unique_id : newauthor) }
      if same_id && !authors.include?(newauthor)
        LOG.debug "#{self}.add_author: author with same ID but not same object exists. Will be duped. Existing author: #{same_id}, is_a?(#{same_id.class.to_s}), newauthor(#{newauthor}), is_a?(#{newauthor.class.to_s})"
        LOG.debug "Existing authors: #{authors.map{|author| author.to_s} * ', '}"
      end
      unless authors.include?(newauthor)
        authors << newauthor
        @moieties = nil
        LOG.debug "New author list: #{authors.map{|author| author.to_s} * ', '}" if same_id
      end
      chapter_list.add_author(newauthor)
    end
    
    def initialize(params={})
      if params.key?(:trash_messages)
        @trash_messages = params[:trash_messages]
        params.delete(:trash_messages)
      end
      return if params.empty?
      params = standardize_params(params)
      
      params.reject! do |param|
        unless allowed_params.include?(param)
          raise(ArgumentError, "Invalid parameter: #{param} = #{params[param]}")
          true
        end
      end
      
      @pages = []
      @check_pages = []
      @replies = []
      @sections = []
      @authors = []
      
      allowed_params.each do |symbol|
        public_send("#{symbol}=", params[symbol]) if params[symbol]
      end
    end
    def smallURL
      @smallURL ||= Chapter.shortenURL(@url)
    end
    def shortURL
      smallURL
    end
    def url=(val)
      @smallURL = nil
      @url=val
    end
    def self.shortenURL(longURL)
      return "" if longURL.nil? or longURL.empty?
      uri = URI.parse(longURL)
      if uri.query and not uri.query.empty?
        query = CGI.parse(uri.query)
        query.delete("style")
        query.delete("view")
        query.delete("per_page")
        query = URI.encode_www_form(query)
        uri.query = (query.empty?) ? nil : query
      end
      uri.host = uri.host.sub(/\.dreamwidth\.org$/, ".dreamwidth").sub('vast-journey-9935.herokuapp.com', 'constellation')
      uri.to_s.sub(/^https?\:\/\//, "").sub(/\.html($|(?=\?))/, "")
    end
    def to_s
      str = "\"#{title}\""
      str += " #{title_extras}" unless title_extras.nil? or title_extras.empty?
      str += ": #{smallURL}"
    end
    
    def self.fauxID(chapter)
      return unless chapter.url.present? && chapter.entry.present?
      url = chapter.url
      entry = chapter.entry
      thread = chapter.thread
      str = ''
      if url['.dreamwidth.org/']
        str << url.split('.dreamwidth.org/').first.split('/').last
        str << '#' + entry.id
        str << '#' + thread if thread
      elsif url['vast-journey-9935.herokuapp.com/']
        str << 'constellation'
        str << '#' + entry.id
      end
      str
    end
    def fauxID
      Chapter.fauxID(self)
    end
    
    def as_json(options={})
      hash = {}
      LOG.debug "Chapter.as_json (title: '#{title}', url: '#{url}')"
      self.instance_variables.each do |var|
        var_str = (var.is_a? String) ? var : var.to_s
        if var_str[0] == '@' and var_str[1] != '@'
          var_str = var_str[1..-1]
          var_sym = var_str.to_sym
        elsif var.is_a?(Symbol)
          var_sym = var
        else
          var_sym = var_str.to_sym
        end
        hash[var_sym] = self.instance_variable_get var unless serialize_ignore?(var_sym)
      end
      if @authors
        hash[:authors] = @authors.map{|author| author.is_a?(Author) ? author.unique_id : author}
      end
      hash
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
        var = var.to_s unless var.is_a?(String)
        self.instance_variable_set('@'+var, val) unless var == "replies" or var == "entry"
      end
      
      LOG.debug "Chapter.from_json! (title: '#{title}', url: '#{url}')"
      
      @processed.map! {|thing| thing.to_s.to_sym } if @processed and @processed.is_a?(Array)
      
      self.authors = [] if @trash_messages
      self.authors
      
      if not @trash_messages
        entry = json_hash['entry']
        replies = json_hash['replies']
        if entry
          entry_hash = entry
          entry_hash['post_type'] = PostType::ENTRY
          entry_hash['chapter'] = self
          entry = Entry.new
          entry.from_json! entry_hash
          self.entry = entry
        end
        if replies
          self.replies = []
          replies.each do |reply_hash|
            reply_hash['post_type'] = PostType::REPLY
            reply_hash['chapter'] = self
            reply = Comment.new
            reply.from_json! reply_hash
            self.replies << reply
          end
        end
      end
      
      @trash_messages = false
    end
  end

  class Face < Model
    attr_accessor :imageURL, :keyword, :unique_id, :chapter_list
    serialize_ignore :allowed_params, :author, :chapter_list
    
    def allowed_params
      @allowed_params ||= [:chapter_list, :imageURL, :keyword, :unique_id, :author]
    end
    
    def user_display
      author.display
    end
    def moiety
      author.moiety
    end
    
    def imageURL=(newval)
      @imageURL = newval.gsub(" ", "%20")
    end
    def author
      return @author if @author and @author.is_a?(Author)
      return unless @author
      @author = chapter_list.get_author_by_id(@author) if chapter_list and not @author.is_a?(Author)
      @author
    end
    def author=(author)
      @author = author
    end
    
    def initialize(params={})
      return if params.empty?
      params = standardize_params(params)
      
      params.reject! do |param|
        unless allowed_params.include?(param)
          raise(ArgumentError, "Invalid parameter: #{param} = #{params[param]}")
          true
        end
      end
      
      raise(ArgumentError, "Unique ID must be given") unless (params.key?(:unique_id) and not params[:unique_id].nil?)
      allowed_params.each do |symbol|
        public_send("#{symbol}=", params[symbol]) if params[symbol]
      end
    end
    def to_s
      "#{user_display}: #{keyword}"
    end
    
    def as_json(options={})
      hash = {}
      self.instance_variables.each do |var|
        var_str = (var.is_a? String) ? var : var.to_s
        if var_str[0] == '@' and var_str[1] != '@'
          var_str = var_str[1..-1]
          var_sym = var_str.to_sym
        elsif var.is_a?(Symbol)
          var_sym = var
        else
          var_sym = var_str.to_sym
        end
        hash[var_sym] = self.instance_variable_get var unless serialize_ignore?(var_sym)
      end
      if @author
        hash[:author] = (author.is_a?(Author) ? author.unique_id : author)
      end
      hash
    end
  end
  
  module PostType
    ENTRY = 0
    REPLY = 1
  end
  
  class Message < Model #post or entry
    attr_accessor :content, :time, :edittime, :id, :chapter, :post_type, :depth, :children, :page_no
    @@date_format = "%Y-%m-%d %H:%M"
    
    def self.message_serialize_ignore
      serialize_ignore :author, :chapter, :parent, :children, :face, :allowed_params, :push_title, :push_author, :post_type
    end
    
    def allowed_params
      @allowed_params ||= [:author, :content, :time, :edittime, :id, :chapter, :parent, :post_type, :depth, :children, :face, :entry_title, :page_no, :author_str]
    end
    
    def unpack!
      author
      face
    end
    
    @push_title = false
    def entry_title
      chapter.entry_title
    end
    def entry_title=(newval)
      if chapter
        chapter.entry_title = newval
      else
        @push_title = true
        @entry_title = newval
      end
    end
    
    def chapter=(newval)
      newval.entry_title=@entry_title if @push_title
      @push_title = false
      newval.add_author(author) if @push_author
      @push_author = false
      @chapter = newval
      keep_old_stuff
      newval
    end
    
    def keep_old_stuff
      unless chapter && chapter.chapter_list
        LOG.error "(No chapter!)" unless chapter
        return
      end
      chapter.chapter_list.keep_old_author(author_id) if author_id
      chapter.chapter_list.keep_old_face(face_id) if face_id
    end
    
    def time
      return unless @time
      return @time unless @time.is_a?(String)
      @time = DateTime.parse(@time)
      return @time
    end
    def time_display
      return unless time
      return time.strftime(@@date_format)
    end
    def edittime
      return unless @edittime
      return @edittime unless @edittime.is_a?(String)
      @edittime = DateTime.parse(@edittime)
      return @edittime
    end
    def edittime_display
      return unless edittime
      return edittime.strftime(@@date_format)
    end
    
    def depth
      if parent and not @depth
        @depth = parent.depth + 1
      end
      @depth ||= 0
    end
    def children
      @children ||= []
    end
    def add_child(val)
      children << val unless children.include?(val)
      val.parent = self unless val.parent == self
    end
    def remove_child(val)
      children.delete(val) if children.include?(val)
      val.parent = nil if val.parent == self
    end
    def moiety
      return "" unless face
      face.moiety
    end
    
    def post_type_str
      if post_type == PostType::ENTRY
        "entry"
      elsif post_type == PostType::REPLY
        "comment"
      else
        "unknown"
      end
    end
    
    def permalink
      site_handler.get_permalink_for(self)
    end
    
    def parent=(newparent)
      return newparent if @parent == newparent
      if @parent
        parent = self.parent
        @parent = nil
        parent.remove_child(self)
      end
      if newparent.is_a?(Message)
        @parent = newparent
        self.parent.add_child(self)
        self.depth = self.parent.depth + 1
      else
        @parent = newparent
      end
      @parent
    end
    def parent
      if @parent.is_a?(Array)
        #from JSON
        if @parent.length == 2
          @parent = @chapter.entry
        else
          parent_id = @parent.last
          LOG.error "Parent of post is nil! #{self}" unless parent_id
          @chapter.replies.reverse_each do |reply|
            if reply.id == parent_id
              @parent = reply
              break
            end
          end
        end
        @parent.children << self unless @parent.children.include?(self)
        @depth = @parent.depth + 1
      end
      @parent
    end
    
    def site_handler
      chapter.site_handler if chapter
    end
    def chapter_list
      chapter.chapter_list if chapter
    end
    
    def face
      return unless @face.present?
      return @face if @face.is_a?(Face)
      
      if chapter_list
        new_face = chapter_list.get_face_by_id(@face)
        new_face = site_handler.get_updated_face(new_face) if site_handler
        if new_face
          @face = new_face
          chapter_list.replace_face(new_face)
        end
      end
      
      if site_handler and (not @face or @face.is_a?(String))
        temp_face = site_handler.get_face_by_id(@face)
        if temp_face
          @face = temp_face
          chapter_list.replace_face(temp_face)
        end
      end
      
      @face.author = author if author and @face and not @face.is_a?(String)
      LOG.error "Failed to generate a face object, is still string (#{@face})" if @face.is_a?(String)
      @face
    end
    def face=(face)
      if (face.is_a?(String) or face.is_a?(Face))
        @face = face
      else
        raise(ArgumentError, "Invalid face type. Face: #{face}")
      end
    end
    
    def face_id
      if @face.is_a?(Face)
        @face.unique_id
      else
        @face
      end
    end
    
    @push_author = false
    def author
      return @author if @author and @author.is_a?(Author)
      return unless @author
      if chapter_list and not @author.is_a?(Author)
        temp_author = chapter_list.get_author_by_id(@author)
        @author = temp_author if temp_author
      end
      if site_handler and not @author.is_a?(Author)
        temp_author = site_handler.get_author_by_id(@author)
        @author = temp_author if temp_author
      end
      @author
    end
    def author=(author)
      @author = author
      chapter.add_author(self.author) if chapter
      @push_author = true unless chapter
    end
    
    def author_id
      if @author.is_a?(Author)
        @author.unique_id
      else
        @author
      end
    end
    
    def author_str
      return @author_str if @author_str.present?
      return @author.moiety if @author and @author.is_a?(Author)
      return @author.to_s if @author
      return nil
    end
    def author_str=(val)
      @author_str = val
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
      
      raise(ArgumentError, "Content must be given") unless params.key?(:content)
      raise(ArgumentError, "Chapter must be given") unless params.key?(:chapter)
      allowed_params.each do |symbol|
        public_send("#{symbol}=", params[symbol]) if params[symbol]
      end
    end
    def to_s
      if chapter.nil?
        "#{author}##{id} @ #{time}: #{content}"
      elsif post_type
        if post_type == PostType::ENTRY
          "#{chapter.smallURL}##{id}"
        elsif post_type == PostType::REPLY
          "#{chapter.smallURL}##{chapter.entry.id}##{id}"
        end
      else
        "#{chapter.smallURL}##{id}"
      end
    end
    
    def as_json(options={})
      hash = {}
      
      self.instance_variables.each do |var|
        var_str = (var.is_a? String) ? var : var.to_s
        if var_str[0] == '@' and var_str[1] != '@'
          var_str = var_str[1..-1]
          var_sym = var_str.to_sym
        elsif var.is_a?(Symbol)
          var_sym = var
        else
          var_sym = var_str.to_sym
        end
        hash[var_str] = self.instance_variable_get var unless serialize_ignore?(var_sym)
      end
      if @parent
        if @parent.is_a?(Message)
          if @parent.post_type == PostType::ENTRY
            hash['parent'] = [chapter.smallURL, @parent.id]
          else
            hash['parent'] = [chapter.smallURL, (chapter.entry.present? ? chapter.entry.id : nil), @parent.id]
          end
        else
          hash['parent'] = @parent
        end
      end
      if @author
        if @author.is_a?(Author)
          hash['author'] = @author.unique_id
        else
          hash['author'] = @author
        end
      end
      if @face
        if @face.is_a?(Face)
          hash['face'] = @face.unique_id
        else
          hash['face'] = @face
        end
      end
      hash
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
        var = var.to_s unless var.is_a?(String)
        self.instance_variable_set('@'+var, val) unless var == 'parent' or var == 'face' or var == 'author'
      end
      
      if post_type == PostType::ENTRY
        chapter.entry = self
        chapter.entry_title = self.entry_title if self.entry_title
      end
      
      parent = json_hash['parent']
      author = json_hash['author']
      face = json_hash['face']
      
      if parent
        self.parent = parent
        self.parent
      end
      if author
        self.author = author
      end
      if face
        self.face = face
      end
      keep_old_stuff
    end
  end

  class Comment < Message
    message_serialize_ignore
    def initialize(params={})
      super(params)
      self.post_type = PostType::REPLY
    end
  end
  
  class Entry < Message
    message_serialize_ignore
    def initialize(params={})
      super(params)
      self.post_type = PostType::ENTRY
    end
  end
  
  class Author < Model
    attr_accessor :moiety, :name, :screenname, :chapter_list, :display, :unique_id, :default_face
    serialize_ignore :faces, :chapters, :chapter_list, :allowed_params, :default_face, :site_handler
    
    def allowed_params
      @allowed_params ||= [:chapter_list, :moiety, :name, :screenname, :display, :unique_id, :default_face]
    end
    def site_handler
      return @site_handler unless @site_handler.nil?
      handler_type = GlowficSiteHandlers.get_handler_for(self)
      chapter_list.site_handlers[handler_type] ||= handler_type.new(group: group, chapters: chapter_list)
      @site_handler ||= chapter_list.site_handlers[handler_type]
    end
    
    def initialize(params={})
      return if params.empty?
      params = standardize_params(params)
      
      params.reject! do |param|
        unless allowed_params.include?(param)
          raise(ArgumentError, "Invalid parameter: #{param} = #{params[param]}")
          true
        end
      end
      
      raise(ArgumentError, "Display must be given") unless (params.key?(:display) and not params[:display].nil?)
      raise(ArgumentError, "Unique ID must be given") unless (params.key?(:unique_id) and not params[:unique_id].nil?)
      allowed_params.each do |symbol|
        public_send("#{symbol}=", params[symbol]) if params[symbol]
      end
    end
    def to_s
      "#{display}"
    end
    
    def default_face
      return unless @default_face.present?
      return @default_face if @default_face.is_a?(Face)
      
      if chapter_list
        new_face = chapter_list.get_face_by_id(@default_face)
        new_face = site_handler.get_updated_face(new_face) if site_handler
        if new_face
          @default_face = new_face
          chapter_list.replace_face(new_face)
        end
      end
      
      if site_handler and (not @default_face or @default_face.is_a?(String))
        temp_face = site_handler.get_face_by_id(@default_face)
        if temp_face
          @default_face = temp_face
          chapter_list.replace_face(temp_face)
        end
      end
      
      @default_face.author = self if @default_face and not @default_face.is_a?(String)
      LOG.error "Failed to generate a face object for default_face, is still string (#{@default_face})" if @default_face.is_a?(String)
      LOG.error "Default_face was non-nil, now nil? oops." unless @default_face.present?  
      @default_face
    end
    
    def as_json(options={})
      hash = {}
      self.instance_variables.each do |var|
        var_str = (var.is_a? String) ? var : var.to_s
        if var_str[0] == '@' and var_str[1] != '@'
          var_str = var_str[1..-1]
          var_sym = var_str.to_sym
        elsif var.is_a?(Symbol)
          var_sym = var
        else
          var_sym = var_str.to_sym
        end
        hash[var_sym] = self.instance_variable_get var unless serialize_ignore?(var_sym)
      end
      if @default_face
        hash[:default_face] = (@default_face.is_a?(Face) ? @default_face.unique_id : @default_face)
      end
      hash
    end
  end
end
