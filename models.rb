module GlowficEpub
  require 'scraper_utils'
  require 'json'
  require 'date'
  include ScraperUtils

  def self.built_moieties?
    @built_moieties ||= false
  end
  def self.built_moieties=(val)
    @built_moieties = val
  end
  def self.build_moieties
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
        @moieties[moiety_key] << user_element.text.strip.tr('_', '-')
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

  module PostType
    ENTRY = 0
    REPLY = 1
  end

  class Model
    attr_accessor :dirty, :serialize_ignore

    def initialize(options={})
      return if params.empty?
      params = standardize_params(params)

      params.reject! do |param|
        unless allowed_params.include?(param)
          raise(ArgumentError, "Invalid parameter: #{param} = #{params[param]}")
        end
      end
      allowed_params.each do |symbol|
        public_send("#{symbol}=", params[symbol])
      end
    end

    def allowed_params; self.class.allowed_params; end

    def standardize_params(params = {})
      params.keys.each do |param|
        if param.is_a?(String)
          params[param.to_sym] = params.delete(param)
          param = param.to_sym
        end
        if param_transform.key?(param)
          params[param_transform[param]] = params.delete(param)
        end
      end
      params
    end

    def self.dirty_accessors(*method_names)
      GlowficEpub::LOG.debug "Defining dirty accessors for #{self}: #{method_names * ', '}"
      method_names.each do |method_name|
        method_name_str = method_name.to_s
        local_instance_var = '@' + method_name_str
        define_method(method_name_str) do
          instance_variable_get(local_instance_var)
        end
        define_method(method_name_str + '=') do |val|
          instance_variable_set(local_instance_var, val)
          dirty!
          val
        end
      end
    end

    def self.dirty_datetime_accessors(*method_names)
      GlowficEpub::LOG.debug "Defining dirty datetime accessors for #{self}: #{method_names * ', '}"
      method_names.each do |method_name|
        method_name_str = method_name.to_s
        local_instance_var = '@' + method_name_str
        define_method(method_name_str) do
          val = instance_variable_get(local_instance_var)
          to_datetime(val)
        end
        define_method(method_name_str + '=') do |val|
          val = to_datetime(val)
          instance_variable_set(local_instance_var, val)
          dirty!
          val
        end
      end
    end

    def dirty!; @dirty = true; end
    def dirty?; dirty; end

    def to_datetime(val)
      return DateTime.parse(val) if val.is_a?(String)
      return val.to_datetime if val.is_a?(Date)
      val
    end

    def self.serialize_ignore? thing
      return if @serialize_ignore.nil?
      return unless thing.is_a?(String) || thing.is_a?(Symbol)
      thing = thing.to_sym if thing.is_a?(String)
      @serialize_ignore.include?(thing)
    end
    def self.serialize_ignore(*things)
      return @serialize_ignore if things.empty?
      self.serialize_ignore!(*things)
    end
    def self.serialize_ignore!(*things)
      things = things.map do |thing|
        (thing.is_a? String) ? thing.to_sym : thing
      end
      @serialize_ignore ||= []
      @serialize_ignore += things
    end
    def serialize_ignore?(thing); self.class.serialize_ignore?(thing); end

    def self.param_transform(**things)
      return @param_transform || {} if things.empty?
      things.keys.each do |param|
        if param.is_a?(String)
          things[param.to_sym] = things.delete(param)
          param = param.to_sym
        end
        if things[param].is_a?(String)
          things[param] = things[param].to_sym
        end
      end
      @param_transform = things
    end
    def param_transform; self.class.param_transform; end

    def json_hash_from_arg(arg)
      return arg if arg.is_a?(Hash)
      return JSON.parse(arg) if arg.is_a?(String)
      raise(ArgumentError, "Not a string or a hash.")
    end

    def as_json_meta(_options={})
      hash = {}
      self.instance_variables.each do |var|
        var_name = var.to_s[1..-1].to_sym # remove "@" from start
        next if var_name == :dirty || var_name == :old_hash || var_name == :skip_list
        next if serialize_ignore?(var_name)
        hash[var_name] = self.instance_variable_get(var)
      end
      hash
    end

    def as_json(options={})
      as_json_meta(options)
    end

    def from_json! string
      json_hash = json_hash_from_arg(string)
      json_hash.each do |var, val|
        self.instance_variable_set('@'+var.to_s, val)
      end
    end
  end

  class Chapters < Model
    attr_accessor :group, :old_characters, :old_faces, :sort_chapters
    attr_reader :chapters, :faces, :characters, :trash_messages, :site_handlers
    attr_writer :get_sections
    serialize_ignore :site_handlers, :trash_messages, :old_characters, :old_faces, :kept_characters, :kept_faces, :failed_characters, :failed_faces, :unpacked
    def initialize(options = {})
      options[:sort_chapters] ||= options[:sort]
      @group = options[:group]
      @sort_chapters = options[:sort_chapters]
      @trash_messages = options[:trash_messages]

      @chapters = []
      @faces = []
      @characters = []
      @site_handlers = {}
    end

    def get_sections?
      @get_sections ||= false
    end

    def unpack!
      return if @unpacked
      each { |chapter| chapter.unpack! }
      @unpacked = true
    end
    def unpacked?
      @unpacked ||= false
    end

    def add_character(arg)
      characters << arg unless characters.include?(arg)
    end
    def replace_character(arg)
      return arg if characters.include?(arg)
      characters.delete_if { |character| character.unique_id == arg.unique_id }
      add_character(arg)
      arg
    end
    def get_character_by_id(character_id)
      found_character = characters.find { |character| character.unique_id == character_id }
      if old_characters.present? && found_character.nil?
        found_character = old_characters.find { |character| character.unique_id == character_id }
        add_character(found_character) if found_character
      end
      return found_character if found_character

      LOG.debug "chapterlist(#{self}).get_character_by_id(#{character_id.inspect}) ⇒ not present"
    end

    def keep_old_character(character_id)
      return if old_characters.blank?
      @kept_characters ||= {}
      @failed_characters ||= []
      return @kept_characters[character_id] if @kept_characters.key?(character_id)
      return if @failed_characters.include?(character_id)

      found_character = old_characters.find { |character| character.unique_id == character_id }
      if found_character
        add_character(found_character)
        @kept_characters[character_id] = found_character
        return found_character
      end
      LOG.error "Failed to find an old character for ID #{character_id}"
      @failed_characters << character_id
      nil
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
      found_face = faces.find { |face| face.unique_id == face_id }
      if old_faces.present? && found_face.nil?
        old_faces.find { |face| face.unique_id == face_id }
        add_face(found_face) if found_face
      end
      found_face
    end

    def keep_old_face(face_id)
      return if old_faces.blank?
      @kept_faces ||= {}
      @failed_faces ||= []
      return @kept_faces[face_id] if @kept_faces.key?(face_id)
      return if @failed_faces.include?(face_id)

      found_face = old_faces.find { |face| face.unique_id == face_id }
      if found_face.present?
        add_face(found_face)
        @kept_faces[face_id] = found_face
        return found_face
      end
      LOG.error "Failed to find an old face for ID #{face_id}"
      @failed_faces << face_id
      nil
    end

    def add_chapter(arg)
      chapters << arg unless chapters.include?(arg)
      arg.chapter_list = self unless arg.chapter_list == self
      sort_chapters! if sort_chapters
    end

    def sort_chapters!
      # TODO: do better
      chapters.sort! do |chapter1, chapter2|
        sections1 = chapter1.section_sorts.try(:map, &:downcase)
        sections1 = [] unless sections1.present?
        sections2 = chapter2.section_sorts.try(:map, &:downcase)
        sections2 = [] unless sections2.present?

        sections1 <=> sections2
      end
    end

    def <<(arg)
      if (arg.is_a?(Face))
        self.add_face(arg)
      elsif (arg.is_a?(Character))
        self.add_character(arg)
      else
        self.add_chapter(arg)
      end
    end

    def length; chapters.length; end
    def count; chapters.count; end
    def empty?; chapters.empty?; end
    def map(&block); chapters.map(&block); end
    def each(&block); chapters.each(&block); end
    def each_with_index(&block); chapters.each_with_index(&block); end

    def as_json(options={})
      hash = as_json_meta(options)
      chapters = hash[:chapters]
      chaptercount = chapters.length
      hash[:chapters] = []
      LOG.progress("Saving chapters for #{group}", 0, chaptercount)
      chapters.each_with_index do |chapter, i|
        hash[:chapters] << chapter.as_json(options)
        LOG.progress("Saving chapters for #{group}", i+1, chaptercount)
      end
      LOG.progress("Generating JSON for and saving #{group}.")
      hash
    end

    def from_json! string
      json_hash = json_hash_from_arg(string)

      json_hash.each do |var, val|
        self.instance_variable_set('@'+var.to_s, val)
      end

      LOG.debug "Chapters.from_json! (group: #{group})"

      characters = json_hash['characters'] || json_hash['authors']
      faces = json_hash['faces']
      chapters = json_hash['chapters']
      @authors = nil unless @authors.nil?

      @characters = []
      @faces = []
      unless trash_messages
        characters.each do |character_hash|
          character_hash['chapter_list'] = self
          character = Character.new
          character.from_json! character_hash
          add_character(character)
        end

        faces.each do |face_hash|
          face_hash['chapter_list'] = self
          face = Face.new
          face.from_json! face_hash
          add_face(face)
        end
      end

      @chapters = []
      chaptercount = chapters.length
      LOG.progress("Loading chapters", 0, chaptercount)
      chapters.each_with_index do |chapter_hash, i|
        chapter_hash['chapter_list'] = self
        chapter = Chapter.new(trash_messages: trash_messages)
        chapter.from_json! chapter_hash
        @chapters << chapter
        LOG.progress("Loading chapters", i+1, chaptercount)
      end
      LOG.progress("Loaded chapters.")
    end
  end

  class Chapter < Model
    dirty_accessors :title, :title_extras, :thread, :entry_title, :pages, :check_pages, :replies, :characters, :url, :report_flags, :processed, :report_flags_processed, :chapter_list, :processed_output, :check_page_data, :marked_complete
    attr_reader :entry
    dirty_datetime_accessors :time_completed, :time_abandoned, :time_hiatus, :time_new

    param_transform name: :title, name_extras: :title_extras, processed_epub: :processed_output
    serialize_ignore :allowed_params, :site_handler, :chapter_list, :trash_messages, :characters, :moieties, :smallURL, :report_flags_processed

    def initialize(params={})
      super(params)

      @trash_messages = params.delete(:trash_messages)

      @pages = []
      @check_pages = []
      @replies = []
      @sections = []
      @characters = []
    end

    def self.allowed_params
      @allowed_params ||= [:title, :title_extras, :thread, :sections, :entry_title, :entry, :replies, :url, :pages, :check_pages, :characters, :time_completed, :time_hiatus, :time_abandoned, :time_new, :report_flags, :processed, :processed_output, :check_page_data, :get_sections, :section_sorts, :marked_complete]
    end

    def unpack!
      entry.unpack! if entry
      replies.each(&:unpack!) if replies
    end

    def processed=(val)
      dirty!
      @processed_output = []
      @processed=val
    end
    def processed?; processed; end;

    def processed_epub?; processed_output?(:epub); end
    def processed_epub; processed_epub?; end

    def processed_output?(thing)
      processed_output.include?(thing.to_s)
    end
    def processed_output(thing=nil)
      return processed_output?(thing) unless thing.nil?
      @processed_output ||= []
    end
    def processed_output_add(thing)
      dirty!
      processed_output << thing.to_s
    end
    def processed_output_delete(thing)
      dirty!
      processed_output.delete_if { |val| val == thing.to_s }
    end

    def get_sections?
      return @get_sections unless @get_sections.nil?
      chapter_list.try(:get_sections?)
    end
    def get_sections=(val)
      return val if @get_sections == val
      dirty!
      @get_sections = val
    end

    def sections
      if @sections.present?
        @sections = [@sections] if @sections.is_a?(String)
        return @sections
      end

      @sections = section_sorts
      @sections = @sections.map do |section|
        temp = section.to_s
        if temp.start_with?('AAA')
          temp = temp.sub(/^AAA[A-C]+-\d+-/, '')
        elsif temp[/^ZZ+/]
          temp = temp.sub(/^ZZ+-/, '')
        end
        temp
      end if @sections.present?
      @sections
    end
    def sections=(val)
      self.section_sorts=val
    end

    def section_sorts
      @section_sorts ||= @sections || []
    end
    def section_sorts=(val)
      return val if @section_sorts == val
      val = [val] if val.is_a?(String)
      dirty!
      @sections = nil
      @section_sorts = val
    end

    def report_flags_processed?; report_flags_processed; end

    def check_page_data
      @check_page_data ||= {}
    end
    def check_page_data_set(index, val)
      dirty!
      @check_page_data[index] = val
    end

    def group; chapter_list.group; end
    def site_handler
      return @site_handler unless @site_handler.nil?
      handler_type = GlowficSiteHandlers.get_handler_for(self)
      chapter_list.site_handlers[handler_type] ||= handler_type.new(group: group, chapters: chapter_list)
      @site_handler ||= chapter_list.site_handlers[handler_type]
    end

    def check_pages
      return @check_pages if @check_pages.present? || pages.blank?
      if url[/\.dreamwidth\.org/]
        if pages.length > 1
          [pages.last, pages.first]
        else
          pages
        end
      elsif url['vast-journey-9935.herokuapp.com'] || url['glowfic.com']
        [set_url_params(clear_url_params(url), {page: :last, per_page: 25})]
      else
        pages
      end
    end

    def replies=(newval)
      dirty!
      @replies = newval
      @characters = []
      @replies.each do |reply|
        reply.chapter = self
      end
      @replies
    end
    def entry=(newval)
      dirty!
      @entry = newval
      @entry.chapter = self
      @entry
    end

    def characters
      @characters ||= []
      return @characters unless @characters.detect { |thing| thing.is_a?(String) }

      dirty!
      premap = @characters
      @characters = @characters.map { |character| (character.is_a?(String)) ? chapter_list.get_character_by_id(character) : character }
      if @characters.select { |thing| thing.nil? }.present?
        LOG.error "#{self} has a nil character post-mapping.\n#{premap * ', '}\n⇒ #{@characters * ', '}"
      end
      @characters
    end

    def chapter_list=(newval)
      @chapter_list = newval
      replies.each(&:keep_old_stuff)
      entry.try(:keep_old_stuff)
      newval
    end

    def time_new_set?; !@time_new.nil?; end
    def time_new
      to_datetime(@time_new) || entry.try(:time)
    end

    def moieties
      return @moieties if @moieties.present?
      @moieties = []
      characters.each do |character|
        (LOG.error "nil character for #{self}"; next) unless character
        @moieties += character.moieties
      end
      @moieties.uniq!
      @moieties.sort!
      @moieties
    end

    def add_character(newcharacter)
      unless newcharacter
        LOG.error "add_character(nil) for #{self}"
        puts caller
        return
      end
      same_id = characters.detect { |character| (character.is_a?(Character) ? character.unique_id : character) == (newcharacter.is_a?(Character) ? newcharacter.unique_id : newcharacter) }
      if same_id && !characters.include?(newcharacter)
        LOG.debug "#{self}.add_character: distinct character with same ID exists. Will be duped. Existing character: #{same_id}, is_a?(#{same_id.class}), newcharacter(#{newcharacter}), is_a?(#{newcharacter.class})"
        LOG.debug "Existing characters: #{characters.map(&:to_s) * ', '}"
      end
      unless characters.include?(newcharacter)
        dirty!
        characters << newcharacter
        @moieties = nil
        LOG.debug "New character list: #{characters.map(&:to_s) * ', '}" if same_id
      end
      chapter_list.add_character(newcharacter)
    end

    def smallURL
      @smallURL ||= shortenURL(@url)
    end
    def shortURL; smallURL; end

    def url=(val)
      dirty!
      @smallURL = nil
      @url = val
    end

    def to_s
      str = "\"#{title}\""
      str += " #{title_extras}" unless title_extras.blank?
      str += ": #{smallURL}"
      str
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
      elsif url['vast-journey-9935.herokuapp.com/'] || url['glowfic.com']
        str << 'constellation'
        str << '#' + entry.id
      end
      str
    end
    def fauxID; Chapter.fauxID(self); end

    def as_json(options={})
      dirtiable = !is_huge_cannot_dirty(chapter_list)
      return @old_hash if dirtiable && @old_hash && !dirty?
      LOG.debug "Chapter.as_json (title: '#{title}', url: '#{url}')"
      hash = as_json_meta(options)
      if @characters
        hash[:characters] = @characters.map { |character| character.is_a?(Character) ? character.unique_id : character }
      end
      if dirtiable
        @old_hash = hash
        @dirty = false
      end
      hash
    end
    def from_json! string
      json_hash = json_hash_from_arg(string)

      json_hash.each do |var, val|
        var = var.to_s
        self.instance_variable_set('@'+var, val) unless var == "replies" || var == "entry"
      end

      LOG.debug "Chapter.from_json! (title: '#{title}', url: '#{url}')"

      @processed.map! {|thing| thing.to_s.to_sym } if @processed.is_a?(Array)

      self.characters = [] if @trash_messages
      self.characters

      @entry_title ||= @title
      @title = nil

      unless @trash_messages
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

      @processed_output = [] unless @processed_output.is_a?(Array)
      @processed_output.uniq!

      @trash_messages = false
      dirty!
    end
  end

  class Face < Model
    attr_accessor :imageURL, :keyword, :unique_id, :chapter_list
    attr_writer :character
    serialize_ignore :allowed_params, :character, :chapter_list

    def initialize(params={})
      return if params.empty?
      super(params)

      raise(ArgumentError, "Unique ID must be given") unless params[:unique_id]
    end

    def self.allowed_params
      @allowed_params ||= [:chapter_list, :imageURL, :keyword, :unique_id, :character]
    end

    def user_display; character.display; end
    def moiety; character.moiety; end

    def imageURL=(newval)
      @imageURL = newval.gsub(' ', '%20')
    end

    def character
      return @character if @character.nil? || @character.is_a?(Character)
      @character = chapter_list.get_character_by_id(@character) if @chapter_list
    end

    def to_s
      "#{user_display}: #{keyword}"
    end

    def as_json(options={})
      hash = as_json_meta(options)
      if @character
        hash[:character] = (character.is_a?(Character) ? character.unique_id : character)
      end
      hash
    end
  end

  class Message < Model #post or entry
    @@date_format = "%Y-%m-%d %H:%M"

    dirty_accessors :content, :time, :edittime, :id, :chapter, :post_type, :depth, :children, :page_no, :author_str

    def self.message_serialize_ignore
      serialize_ignore :character, :chapter, :parent, :children, :face, :allowed_params, :push_title, :push_character, :post_type
    end

    def initialize(params={})
      return if params.empty?
      super(params)

      @push_title = false
      @push_character = false
      @children = []

      raise(ArgumentError, "Content must be given") unless params.key?(:content)
      raise(ArgumentError, "Chapter must be given") unless params.key?(:chapter)
    end

    def self.allowed_params
      @allowed_params ||= [:character, :content, :time, :edittime, :id, :chapter, :parent, :post_type, :depth, :children, :face, :entry_title, :page_no, :author_str]
    end

    def unpack!
      character
      face
    end

    def dirty!
      @dirty = true
      chapter.dirty! if chapter
    end

    def site_handler; chapter.try(:site_handler); end
    def chapter_list; chapter.try(:chapter_list); end

    def entry_title; chapter.entry_title; end
    def entry_title=(newval)
      dirty!
      if chapter
        chapter.entry_title = newval
      else
        @push_title = true
        @entry_title = newval
      end
      newval
    end

    def chapter=(newval)
      newval.entry_title = @entry_title if @push_title
      @push_title = false
      @chapter.dirty! if @chapter
      newval.add_character(character) if @push_character
      @push_character = false
      @chapter = newval
      keep_old_stuff
      dirty!
      newval
    end

    def keep_old_stuff
      unless chapter && chapter.chapter_list
        LOG.error "(No chapter!)" unless chapter
        return
      end
      chapter.chapter_list.keep_old_character(character_id) if character_id
      chapter.chapter_list.keep_old_face(face_id) if face_id
    end

    def time
      return @time unless @time.is_a?(String)
      @time = DateTime.parse(@time)
    end
    def time_display
      time.try(:strftime, @@date_format)
    end
    def edittime
      return @edittime unless @edittime.is_a?(String)
      @edittime = DateTime.parse(@edittime)
    end
    def edittime_display
      edittime.try(:strftime, @@date_format)
    end

    def depth
      if parent && !@depth
        @depth = parent.depth + 1
      end
      @depth ||= 0
    end

    def add_child(val)
      children << val unless children.include?(val)
      val.parent = self unless val.parent == self
    end
    def remove_child(val)
      children.delete(val)
      val.parent = nil if val.parent == self
    end

    def moiety; character.try(:moiety) || ''; end

    def post_type_str
      if post_type == PostType::ENTRY
        "entry"
      elsif post_type == PostType::REPLY
        "comment"
      else
        "unknown"
      end
    end

    def permalink; site_handler.get_permalink_for(self); end

    def parent=(newparent)
      return newparent if @parent == newparent
      dirty!

      if @parent
        oldparent = self.parent
        @parent = nil
        oldparent.remove_child(self)
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
      return @parent unless @parent.is_a?(Array)

      # load from JSON:
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
      self.parent = @parent
    end

    def face
      return @face if @face.nil? || @face.is_a?(Face)

      if chapter_list
        new_face = chapter_list.get_face_by_id(@face)
        new_face = site_handler.get_updated_face(new_face) if site_handler
        if new_face
          @face = new_face
          chapter_list.replace_face(new_face)
        end
      end

      if site_handler && @face.is_a?(String)
        temp_face = site_handler.get_face_by_id(@face)
        if temp_face
          @face = temp_face
          chapter_list.replace_face(temp_face)
        end
      end

      @face.character = character if character && @face.is_a?(Face)
      LOG.error "Failed to generate a face object, is still string (#{@face})" if @face.is_a?(String)
      @face
    end
    def face=(face)
      return face if @face == face
      raise(ArgumentError, "Invalid face type. Face: #{face}") if face && !face.is_a?(String) && !face.is_a?(Face)

      dirty!
      @face = face
    end

    def face_id
      return @face unless @face.is_a?(Face)
      @face.unique_id
    end

    def character
      return @character if @character.nil? || @character.is_a?(Character)
      temp = chapter_list.try(:get_character_by_id, @character)
      temp ||= site_handler.try(:get_character_by_id, @character)
      @character = temp || @character
    end
    def character=(character)
      dirty!
      @character = character
      @push_character = true unless chapter
      chapter.try(:add_character, self.character)
      @character
    end

    def character_id
      return @character unless @character.is_a?(Character)
      @character.unique_id
    end

    def author_str
      return @author_str if @author_str.present?
      return @character.moieties * ', ' if @character.is_a?(Character)
      @character.try(:to_s)
    end

    def to_s
      if chapter.nil?
        "#{character}##{id} @ #{time}"
      elsif post_type == PostType::ENTRY
        "#{chapter.smallURL}##{id}"
      elsif post_type == PostType::REPLY
        "#{chapter.smallURL}##{chapter.entry.id}##{id}"
      else
        "#{chapter.smallURL}##{id}"
      end
    end

    def as_json(options={})
      dirtiable = !is_huge_cannot_dirty(chapter_list)
      return @old_hash if dirtiable && @old_hash && !dirty?
      hash = as_json_meta(options)

      if @parent
        if @parent.is_a?(Message)
          if @parent.post_type == PostType::ENTRY
            hash[:parent] = [chapter.smallURL, @parent.id]
          else
            hash[:parent] = [chapter.smallURL, (chapter.entry.present? ? chapter.entry.id : nil), @parent.id]
          end
        else
          hash[:parent] = @parent
        end
      end

      if @character
        if @character.is_a?(Character)
          hash[:character] = @character.unique_id
        else
          hash[:character] = @character
        end
      end

      if @face
        if @face.is_a?(Face)
          hash[:face] = @face.unique_id
        else
          hash[:face] = @face
        end
      end

      if dirtiable
        @old_hash = hash
        @dirty = false
      end
      hash
    end

    def from_json! string
      json_hash = json_hash_from_arg(string)

      json_hash.each do |var, val|
        var = var.to_s
        self.instance_variable_set('@'+var, val) unless var == 'parent' or var == 'face' or var == 'character'
      end

      if post_type == PostType::ENTRY
        chapter.entry = self
        chapter.entry_title = self.entry_title if self.entry_title
      end

      parent = json_hash['parent']
      character = json_hash['character'] || json_hash['author']
      face = json_hash['face']
      @author = nil unless @author.nil?

      if parent
        self.parent = parent
        self.parent
      end
      if character
        self.character = character
      end
      if face
        self.face = face
      end
      keep_old_stuff
      dirty!
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

  class Character < Model
    attr_accessor :name, :screenname, :chapter_list, :display, :unique_id, :default_face
    serialize_ignore :faces, :chapters, :chapter_list, :allowed_params, :default_face, :site_handler

    def initialize(params={})
      return if params.empty?
      super(params)

      raise(ArgumentError, "Display must be given") unless params[:display]
      raise(ArgumentError, "Unique ID must be given") unless params[:unique_id]
    end

    def self.allowed_params
      @allowed_params ||= [:chapter_list, :moiety, :name, :screenname, :display, :unique_id, :default_face]
    end

    def site_handler
      return @site_handler unless @site_handler.nil?
      handler_type = GlowficSiteHandlers.get_handler_for(self)
      chapter_list.site_handlers[handler_type] ||= handler_type.new(group: group, chapters: chapter_list)
      @site_handler ||= chapter_list.site_handlers[handler_type]
    end

    def to_s; display.to_s; end

    def default_face_id
      return @default_face if @default_face.nil? || @default_face.is_a?(String)
      @default_face.unique_id
    end
    def default_face
      return @default_face if @default_face.nil? || @default_face.is_a?(Face)

      if chapter_list
        new_face = chapter_list.get_face_by_id(@default_face)
        new_face = site_handler.get_updated_face(new_face) if site_handler
        if new_face
          @default_face = new_face
          chapter_list.replace_face(new_face)
        end
      end

      if site_handler && @default_face.is_a?(String)
        temp_face = site_handler.get_face_by_id(@default_face)
        if temp_face
          @default_face = temp_face
          chapter_list.replace_face(temp_face)
        end
      end

      @default_face.character = self if @default_face && !@default_face.is_a?(String)
      LOG.error "Failed to generate a face object for default_face, is still string (#{@default_face})" if @default_face.is_a?(String)
      @default_face
    end

    def moiety
      return @moiety if @moieties.blank?
      @moieties.map { |m| m.gsub(/[^\w]/,'_') } * '_'
    end
    def moiety=(val)
      if val.is_a?(Array)
        @moieties = val.uniq
        @moiety = nil
      else
        @moiety = val
        @moieties = nil
      end
    end
    def moieties
      return [@moiety] if @moieties.blank?
      @moieties
    end

    def as_json(options={})
      hash = as_json_meta(options)
      hash.delete(:moiety) if hash[:moieties]
      hash.delete(:moieties) if hash[:moiety]
      if @default_face
        hash[:default_face] = (@default_face.is_a?(Face) ? @default_face.unique_id : @default_face)
      end
      hash
    end
  end
end
