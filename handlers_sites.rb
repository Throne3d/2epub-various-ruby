﻿module GlowficSiteHandlers
  require 'scraper_utils'
  require 'models'
  require 'mechanize'
  include ScraperUtils
  include GlowficEpub::PostType

  def self.get_handler_for(thing)
    site_handlers = GlowficSiteHandlers.constants.map {|c| GlowficSiteHandlers.const_get(c) }
    site_handlers.select! {|c| c.is_a?(Class) && c < GlowficSiteHandlers::SiteHandler }
    chapter_handlers = site_handlers.select {|c| c.handles? thing}
    return chapter_handlers.first if chapter_handlers.length == 1
    chapter_handlers
  end

  class SiteHandler
    include GlowficEpub
    attr_reader :group, :chapter_list

    def self.handles?(_chapter); false; end
    def handles?(chapter); self.class.handles?(chapter); end

    def initialize(options = {})
      @group = options[:group]
      @group_folder = "web_cache"
      @group_folder += "/#{@group}" if @group
      @chapter_list = options[:chapters] || options[:chapter_list]
      @chapter_list = GlowficEpub::Chapters.new if @chapter_list.nil? || (@chapter_list.is_a?(Array) && @chapter_list.empty?)
      @download_count = 0
      @downcache = {}
      @giricache = {}
    end

    def get_updated(_chapter); nil; end
    def message_attributes(options = {})
      return @message_attributes unless options.present?
      only_attrs = options[:attributes] || options[:only] || options[:only_attrs]
      except_attrs = options[:except] || options[:except_attrs]
      raise("Not allowed both :only and :except on get_replies; #{only_attrs * ','} and #{except_attrs * ','}") if only_attrs && except_attrs

      message_attributes = msg_attrs
      if only_attrs
        message_attributes = only_attrs
      elsif except_attrs
        message_attributes = msg_attrs.reject! {|thing| except_attrs.include?(thing)}
      end
      message_attributes.uniq!
      @message_attributes = message_attributes
    end
    def already_processed(chapter, options = {})
      message_attributes(options)
      return unless chapter.processed.try(:is_a?, Array) && chapter.processed.contains_all?(message_attributes)

      if chapter.replies.empty?
        LOG.error "#{chapter.title}: cached data contains no replies; not using"
        return
      end

      msg_str = "#{chapter.title}: unchanged, cached data used"
      if block_given?
        yield msg_str
      elsif notify
        LOG.info msg_str
      end
      true
    end

    def down_or_cache(page, options = {})
      where = options[:where]
      @downcache[where] ||= []

      downd = @downcache[where].include?(page)
      options[:replace] = !downd
      data = get_page_data(page, options)
      return data if downd

      @download_count+=1
      @downcache[where] << page
      data
    end
    def giri_or_cache(page, options = {})
      LOG.debug "giri_or_cache(\"#{page}\"" + (options.empty? ? "" : ", #{options}") + ")"
      where = options[:where]
      replace = options.fetch(:replace, true)
      @giricache[where] ||= {}
      return @giricache[where][page] if @giricache[where].key?(page)

      predone = has_cache?(page, options)

      options[:headers] ||= {"Accept" => "text/html"}
      data = replace ? down_or_cache(page, options) : get_page_data(page, options)
      giri = Nokogiri::HTML(data)
      @giricache[where][page] = giri if predone
      giri
    end
    def remove_cache(page, options = {})
      @downcache[options[:where]].try(:delete, page)
    end
    def remove_giri_cache(page, options = {})
      @giricache[options[:where]].try(:delete, page)
    end
    alias_method :nokogiri_or_cache, :giri_or_cache

    def has_cache?(page, options={})
      @downcache[options[:where]].try(:include?, page)
    end

    def save_down(page, data, options={})
      where = options[:where]
      @downcache[where] ||= []
      @downcache[where] << page unless @downcache[where].include?(page)

      loc = get_page_location(page, options)
      open(loc, 'w') do |f|
        f.write data
      end
      data
    end

    def msg_attrs
      @msg_attrs ||= [:time, :edittime, :character, :face]
    end
  end

  class DreamwidthHandler < SiteHandler
    attr_reader :download_count
    def self.handles?(thing)
      return if thing.nil?
      return thing.unique_id.start_with?('dreamwidth#') if thing.is_a?(GlowficEpub::Character)

      chapter_url = thing.url if thing.is_a?(GlowficEpub::Chapter)
      chapter_url ||= thing
      return if chapter_url.blank?

      uri = URI.parse(chapter_url)
      uri.host.end_with?('dreamwidth.org')
    end

    def initialize(options = {})
      super options
      @face_cache = {} # {"alicornutopia" => {"pen" => "(url)"}}
      @face_id_cache = {} # {"alicornutopia#pen" => "(url)"}
      # When retrieved in get_face_by_id
      @face_url_cache = {}
      @face_param_cache = {}
      @face_update_failures = []
      @character_id_cache = {}
      @character_param_cache = {}

      @page_list = []
      @repeated_page_cache = {}

      @moiety_cache = {}

      @downloaded = []

      @mech_agent = Mechanize.new
    end

    def get_comment_link(comment)
      partial = comment.at_css('> .dwexpcomment > .partial')
      if partial
        full = nil
        comm_link = partial.at_css('.comment-title').try(:at_css, 'a').try(:[], :href)
      else
        full = comment.at_css('> .dwexpcomment > .full')
        comm_link = full.try(:at_css, '.commentpermalink').try(:at_css, 'a').try(:[], :href)
      end

      yield partial, full, comm_link if block_given?
      return unless comm_link

      params = {style: :site}
      params[:thread] = get_url_param(comm_link, "thread")
      comm_link = set_url_params(clear_url_params(comm_link), params)
      return comm_link
    end
    def get_permalink_for(message)
      # x.dreamwidth.org/1234.html?view=flat
      return set_url_params(clear_url_params(message.chapter.url), {view: :flat}) if message.post_type == "PostType::ENTRY"
      # x.dreamwidth.org/1234.html?page=5&view=flat#comment-67890
      return set_url_params(clear_url_params(message.chapter.url), {view: :flat, page: message.page_no}) + "#comment-#{message.id}" if message.page_no
      # x.dreamwidth.org/1234.html?thread=67890#comment-67890
      set_url_params(clear_url_params(message.chapter.url), {thread: message.id}) + "#comment-#{message.id}"
    end
    def get_undiscretioned(url, options = {})
      current_page = options.delete(:current_page) || options.delete(:current)
      if current_page.present?
        current_page = Nokogiri::HTML(current_page)
      else
        current_page = giri_or_cache(url, options)
      end

      content = current_page.at_css('#content')

      text_thing = 'Discretion Advised'
      nsfw_warning = content.at_css('.panel.callout').try(:at_css, '.text-center').try(:text)
      return current_page unless nsfw_warning.try(:[], text_thing)

      LOG.debug "Got a discretion advised – trying to fix with Mechanize"
      page = @mech_agent.get(url)
      sleep 0.05
      discretion_form = page.forms.select{|form| form.action["/adult_concepts"]}.first

      remove_giri_cache(url, options)
      save_down(url, (discretion_form.try(:submit) || page).content, options)
      current_page = giri_or_cache(url, options)

      nsfw_warning = current_page.at_css('.panel.callout').try(:at_css, '.text-center').try(:text)
      if nsfw_warning.try(:[], text_thing)
        LOG.error "Failed to fix discretion advised warning for page #{url}"
        return
      end

      LOG.debug "Fixed a discretion advised warning"
      current_page
    end

    # returns comment_count
    def find_check_pages(chapter, main_page_stuff)
      main_page_content = main_page_stuff.at_css('#content')
      comments = main_page_content.css('.comment-thread')
      prev_chain = []
      prev_depth = 0
      comm_depth = 0
      comment_count = 0
      comments.each do |comment|
        comment_count += 1
        prev_chain = prev_chain.drop(prev_chain.length - 3) if prev_chain.length > 3
        (LOG.error "Error: failed comment depth"; next) unless comment[:class]["comment-depth-"]

        comm_depth = 0
        comm_depth = comment[:class].split('comment-depth-').last.split(/\s+/).first.to_i

        last_comment = comment == comments.last
        if comm_depth > prev_depth
          prev_chain << comment
          prev_depth = comm_depth
          next unless last_comment
        else
          LOG.debug "comment depth has decreased (#{prev_depth} -> #{comm_depth}); new branch." unless last_comment
        end

        upper_comment = prev_chain.first
        @cont = false
        comm_link = get_comment_link(upper_comment) do |_partial, _full, c_link|
          unless c_link
            LOG.error "Error: failed upper comment link (for depth #{comm_depth})"
            @cont = true
          end
        end
        next if @cont

        chapter.check_pages << comm_link
        LOG.debug "Added to chapter check_pages: #{comm_link}"
        break if last_comment

        prev_chain = [comment]
        prev_depth = comm_depth
      end
      comment_count
    end

    def get_full(chapter, _options = {})
      if chapter.is_a?(GlowficEpub::Chapter)
        params = {style: :site}
        params[:thread] = chapter.thread if chapter.thread
        chapter_url = set_url_params(clear_url_params(chapter.url), params)
      end
      chapter_url ||= chapter
      return unless self.handles?(chapter_url)

      page_urls = []
      params = {style: :site, view: :flat, page: 1}
      first_page = set_url_params(clear_url_params(chapter.url), params)
      first_page_stuff = get_undiscretioned(first_page, where: @group_folder)

      unless first_page_stuff
        @error = "Page failed to load (discretion advised warning?)"
        @success = false
        return
      end

      first_page_content = first_page_stuff.at_css('#content')

      page_count = first_page_content.try(:at_css, '.comment-pages').try(:at_css, '.page-links').try(:at_css, 'a:last').try(:text).try(:strip)
                  .try(:gsub, '[', '').try(:gsub, ']', '').try(:to_i)
      page_count ||= 1

      1.upto(page_count).each do |num|
        params[:page] = num
        this_page = set_url_params(clear_url_params(chapter.url), params)
        down_or_cache(this_page, where: @group_folder)
        page_urls << this_page
      end

      chapter.processed = false if chapter.is_a?(GlowficEpub::Chapter)

      @success = true
      return page_urls
    end
    def get_updated(chapter, options = {})
      return unless self.handles?(chapter)
      notify = options.fetch(:notify, true)

      is_new = true
      prev_pages = chapter.pages
      check_pages = chapter.check_pages
      if prev_pages.present?
        is_new = false

        @download_count = 0
        changed = false
        same_comment_count = false
        check_pages.reverse.each_with_index do |check_page, i|
          if check_page == check_pages.first && same_comment_count
            LOG.debug "Same non-main pages & comment count, skipping main page."
            next
          end

          page_location = get_page_location(check_page, where: @group_folder)
          was_file = File.file?(page_location)

          page_old_data = get_page_data(check_page, replace: false, where: @group_folder)
          unless was_file
            LOG.debug "check page #{i}, #{check_page}, didn't exist in the group folder"
            changed = true
            break
          end

          page_new = get_undiscretioned(check_page, where: 'temp')
          page_old = Nokogiri::HTML(page_old_data)

          page_cache = (check_page == check_pages.first) ? nil : chapter.check_page_data[check_page]
          page_cache = Nokogiri::HTML(page_cache) if page_cache

          chapter.check_page_data_set(check_page, page_old_data) unless page_cache || check_page == check_pages.first

          unless page_new
            @error = "Page failed to load (discretion advised warning?)"
            @success = false
            return
          end

          old_content = page_old.at_css('#content')
          new_content = page_new.at_css('#content')
          cache_content = page_cache.at_css('#content') if page_cache

          old_comment_count = old_content.at_css('.entry-readlink').try(:text).try(:strip).try(:[], /\d+/)
          new_comment_count = new_content.at_css('.entry-readlink').try(:text).try(:strip).try(:[], /\d+/)
          cache_comment_count = cache_content.at_css('.entry-readlink').try(:text).try(:strip).try(:[], /\d+/) if page_cache
          same_comment_count = true if (old_comment_count && new_comment_count && old_comment_count == new_comment_count) && (page_cache.blank? || cache_comment_count == old_comment_count)

          old_content.at_css(".entry-interaction-links").try(:remove)
          new_content.at_css(".entry-interaction-links").try(:remove)
          cache_content.at_css(".entry-interaction-links").try(:remove) if page_cache

          changed = (old_content.inner_html != new_content.inner_html)
          if changed
            LOG.debug "check page #{i}, #{check_page}, was different"
            break
          end
          if page_cache && !changed
            changed2 = (old_content.inner_html != cache_content.inner_html)
            if changed2
              LOG.info "check page cache in JSON (#{i}, #{check_page}) was different. other cache wasn't. fixing."
              changed = changed2
              break
            end
          end
          LOG.debug "check page #{i} was not different"
        end

        LOG.debug "#{changed ? '' : 'not '}changed!"

        pages_exist = true
        prev_pages.each_with_index do |page_url, i|
          page_loc = get_page_location(page_url, where: @group_folder)
          next if File.file?(page_loc)

          pages_exist = false
          LOG.error "Failed to find a file (page #{i}) for chapter #{chapter}. Will get again."
          break
        end #Check if all the pages exist, in case someone deleted them

        LOG.debug "Content is different for #{chapter}" if changed
        if pages_exist && !changed
          msg_str = "#{chapter.title}: #{chapter.pages.length} page#{chapter.pages.length != 1 ? 's' : ''} (checked #{@download_count} page#{@download_count != 1 ? 's' : ''})"
          if block_given?
            yield msg_str
          elsif notify
            LOG.info msg_str
          end
          return chapter
        end
      end

      chapter.processed = false

      #Hasn't been done before, or it's outdated, or some pages were deleted; re-get.
      @download_count = 0
      @success = false
      pages = get_full(chapter, options.merge({new: !changed}))

      params = {style: :site}
      params[:thread] = chapter.thread if chapter.thread
      main_page = set_url_params(clear_url_params(chapter.url), params)

      main_page_stuff = get_undiscretioned(main_page, where: @group_folder)
      unless main_page_stuff
        @error = "Page failed to load (discretion advised warning?)"
        @success = false
      end

      comment_count = 0
      if main_page_stuff
        #Check the comments and find each branch-end and get a link to them all
        chapter.check_pages = [main_page]
        comment_count = find_check_pages(chapter, main_page_stuff)

        chapter.pages = pages
        chapter.check_page_data = {}
        chapter.check_pages.each do |check_page|
          if has_cache?(check_page, where: 'temp')
            temp_data = down_or_cache(check_page, where: 'temp')
            save_down(check_page, temp_data, where: @group_folder)
          else
            down_or_cache(check_page, where: @group_folder)
          end
          unless check_page == chapter.check_pages.first
            chapter.check_page_data_set(check_page, down_or_cache(check_page, where: @group_folder))
          end
        end
      end

      page_count = (comment_count < 50) ? 1 : (comment_count / 25.0).ceil
      if @success
        msg_str = "#{is_new ? 'New:' : 'Updated:'} #{chapter.title}: #{page_count} page#{page_count != 1 ? 's' : ''} (Got #{@download_count} page#{@download_count != 1 ? 's' : ''})"
        if block_given?
          yield msg_str
        elsif notify
          LOG.info msg_str
        end
        return chapter
      end

      msg_str = "ERROR: #{chapter.title}: #{@error}"
      LOG.error msg_str
      return chapter
    end

    def get_moiety_by_profile(profile)
      return @moiety_cache[profile] if @moiety_cache.key?(profile)
      user_id = profile.gsub('_', '-')
      return @moiety_cache[user_id] if @moiety_cache.key?(user_id)

      moieties = []
      GlowficEpub.moieties.each do |author, account_list|
        moieties << author if account_list.include?(profile) || account_list.include?(user_id)
      end

      LOG.error "No moiety for #{profile}" if moieties.empty?
      @moiety_cache[user_id] = moieties
    end

    def set_face_cache(face)
      face_id = face.unique_id
      face_id = face_id[0..-2].strip if face_id.end_with?(',')
      user_profile = face_id.split('#').first
      user_hash = @face_cache[user_profile] || @face_cache[user_profile.gsub('_', '-')]
      if user_hash
        user_hash[face.keyword] = face
        user_hash[:default] = face if user_hash[:default].try(:unique_id) == face.unique_id
      end
      @chapter_list.replace_face(face)
      @face_url_cache[face.imageURL.sub(/https?:\/\//, '')] = face
      @face_id_cache[face_id] = face
    end
    def get_face_by_id(face_id, options={})
      try_chapterface = options.key?(:try_chapterface) ? options[:try_chapterface] : true
      face_id = face_id[0..-2].strip if face_id.end_with?(',')
      return @face_id_cache[face_id] if @face_id_cache.key?(face_id)
      face_url = options.key?(:face_url) ? options[:face_url] : (options.key?(:url) ? options[:url] : nil)
      if face_url
        face_url_noprot = face_url.sub(/https?:\/\//, '')
        return @face_url_cache[face_url_noprot] if @face_url_cache.key?(face_url_noprot)
      end
      if try_chapterface
        chapter_face = @chapter_list.try(:get_face_by_id, face_id)
        if chapter_face.present?
          @face_id_cache[face_id] = chapter_face
          @face_url_cache[(face_url || chapter_face.imageURL).sub(/https?:\/\//, '')] = chapter_face
          return chapter_face
        end
      end
      user_profile = face_id.split('#').first
      face_name = face_id.sub("#{user_profile}#", "")
      face_name = "default" if face_name == face_id || face_name == "(Default)"
      @icon_page_errors ||= []
      @icon_errors ||= []
      return if @icon_page_errors.include?(user_profile)

      unless @face_cache.key?(user_profile) || @face_cache.key?(user_profile.gsub('_', '-'))
        user_id = user_profile.gsub('_', '-')

        icon_page = giri_or_cache("http://#{user_id}.dreamwidth.org/icons")
        LOG.debug "nokogiri'd icon page"
        icons = icon_page.at_css('#content').css('.icon-row .icon')
        default_icon = icon_page.at_css('#content').at_css('.icon.icon-default')

        if icons.nil? or icons.empty?
          LOG.error "No icons for #{user_id}."
          @icon_page_errors << user_profile
          return
        end
        (LOG.error "No default icon for #{user_id}.") if default_icon.nil?

        icon_hash = {}
        icons.each do |icon_element|
          icon_img = icon_element.at_css('.icon-image img')
          icon_src = icon_img.try(:[], :src)

          (LOG.error "Failed to find an img URL on the icon page for #{user_id}"; next) if icon_src.nil? or icon_src.empty?

          icon_keywords = icon_element.css('.icon-info .icon-keywords li')

          params = {}
          params[:imageURL] = icon_src
          params[:character] = get_character_by_id(user_profile)

          icon_keywords.each do |keyword_element|
            keyword = keyword_element.text.strip
            keyword = keyword[0..-2].strip if keyword.end_with?(",")
            params[:keyword] = keyword
            params[:unique_id] = "#{user_id}##{params[:keyword]}"
            face = Face.new(params)
            icon_hash[params[:keyword]] = face
            @chapter_list.replace_face(face)
            if icon_element == default_icon
              icon_hash[:default] = face
              params[:character].default_face = face if params[:character] && !params[:character].default_face_id.present?
            end
            @face_param_cache[face.unique_id] = params
            @face_url_cache[icon_src.sub(/https?:\/\//, '')] = face
          end
        end

        LOG.debug "got #{icon_hash.keys.count} icon(s)"

        @face_cache[user_profile] = icon_hash
      end

      icons_hash = @face_cache[user_profile] || @face_cache[user_profile.gsub('_', '-')]
      @face_id_cache[face_id] = icons_hash[face_name] if icons_hash.key?(face_name)
      @face_id_cache[face_id] = icons_hash[:default] if (face_name.downcase == "default" or face_name == :default) and icons_hash.key?(:default)
      return @face_id_cache[face_id] if @face_id_cache.key?(face_id)

      if face_url
        face_url_noprot = face_url.sub(/https?:\/\//, '')
        return @face_url_cache[face_url_noprot] if @face_url_cache.key?(face_url_noprot)
      end

      LOG.error "Failed to find a face for user: #{user_profile} and face: #{face_name}" + (face_url.present? ? " and URL: #{face_url}" : '') unless @icon_errors.include?(face_id)
      @icon_errors << face_id unless @icon_errors.include?(face_id)
      return
    end
    def get_updated_face(face)
      return unless face
      return get_face_by_id(face.unique_id) if @face_param_cache.key?(face.unique_id)

      params = {}
      params[:face_url] = face.imageURL if face.imageURL.present?
      params[:try_chapterface] = false
      done_face = get_face_by_id(face.unique_id, params)
      face_hash = @face_param_cache[(done_face || face).unique_id]
      if face_hash.present?
        face.from_json! face_hash
      elsif done_face.present? && !@face_update_failures.include?(face.unique_id)
        LOG.error "Face was created, param cache was not set. Face not updating despite being supposed to. #{face}"
        @face_update_failures << face.unique_id
      end
      set_face_cache(face)
    end

    def set_character_cache(character)
      character_id = character.unique_id.gsub('_', '-')
      character_id = character_id.sub("dreamwidth#", "") if character_id.start_with?("dreamwidth#")
      @character_id_cache[character_id] = character
    end
    def get_character_by_id(character_id, options={})
      character_id = character_id.gsub('_', '-')
      character_id = character_id.sub("dreamwidth#", "") if character_id.start_with?("dreamwidth#")
      return @character_id_cache[character_id] if @character_id_cache.key?(character_id)

      try_chaptercharacter = options.key?(:try_chaptercharacter) ? options[:try_chaptercharacter] : true

      if try_chaptercharacter
        chapter_character = @chapter_list.try(:get_character_by_id, "dreamwidth##{character_id}")
        if chapter_character.present?
          @character_id_cache[character_id] = chapter_character
          return chapter_character
        end
      end

      char_page = giri_or_cache("http://#{character_id}.dreamwidth.org/profile")
      LOG.debug "nokogiri'd profile page"

      params = {}
      params[:moiety] = get_moiety_by_profile(character_id)

      profile_summary = char_page.at_css('.profile table')
      profile_summary.css('th').each do |th_element|
        if th_element.text["Name:"]
          params[:name] = th_element.next_element.text.strip
        end
      end
      params[:screenname] = character_id
      params[:display] = (params.key?(:name) and params[:name].downcase != params[:screenname].downcase) ? "#{params[:name]} (#{params[:screenname]})" : "#{params[:screenname]}"
      params[:unique_id] = "dreamwidth##{character_id}"


      character = Character.new(params)
      @character_param_cache[character.unique_id] = params
      @character_id_cache[character_id] = character
    end
    def get_updated_character(character)
      return unless character
      return get_character_by_id(character.unique_id) if @character_param_cache.key?(character.unique_id)

      get_character_by_id(character.unique_id, try_chaptercharacter: false)
      character_hash = @character_param_cache[character.unique_id]
      character.from_json! character_hash
      set_character_cache(character)

      character
    end

    def make_message(message_element, options = {})
      #message_element is .comment
      message_attributes = options[:message_attributes] || msg_attrs

      Time.zone = 'UTC'

      message_id = message_element['id'].sub('comment-', '').sub('entry-', '')
      message_type = message_element['id']['entry'] ? PostType::ENTRY : PostType::REPLY

      character_id = message_element.at_css('span.ljuser').try(:[], "lj:user")

      params = {}
      if message_attributes.include?(:edittime)
        edit_element = message_element.at_css('.edittime')
        if edit_element
          edit_text = edit_element.at_css(".datetime").text.strip
          params[:edittime] = DateTime.strptime(edit_text, "%Y-%m-%d %H:%M (%Z)")
          edit_element.remove
        end
      end

      message_content = message_element.at_css('.comment-content, .entry-content')
      params[:content] = message_content.inner_html
      params[:character] = get_character_by_id(character_id) if message_attributes.include?(:character)
      params[:id] = message_id
      params[:chapter] = @chapter

      if message_attributes.include?(:face)
        userpic = message_element.at_css('.userpic').try(:at_css, 'img')
        face_url = ""
        face_name = "default"
        if userpic and userpic["title"]
          if userpic["title"] != character_id
            face_name = userpic["title"].sub("#{character_id}: ", "").split(" (").first
          end
          if userpic["src"]
            face_url = userpic["src"]
          end
        end

        face_id = "#{character_id}##{face_name}"
        params[:face] = get_face_by_id(face_id, face_url: face_url)
        params[:face] = @chapter_list.get_face_by_id(face_id) if params[:face].nil?

        if params[:face].nil? and not face_url.empty?
          face_params = {}
          face_params[:imageURL] = face_url
          face_params[:character] = get_character_by_id(character_id) if message_attributes.include?(:character)
          face_params[:keyword] = face_name
          face_params[:unique_id] = face_id
          face = Face.new(face_params)
          @chapter_list.add_face(face)
          LOG.debug "Face replaced by backup face '#{face}' with URL: #{face_url}"
          params[:face] = face
        end
      end

      if message_type == PostType::ENTRY
        params[:entry_title] = message_element.at_css('.entry-title').text.strip

        if message_attributes.include?(:time)
          time_text = message_element.at_css('.datetime').text.strip
          time_text = time_text[1..-1].strip if time_text.start_with?("@")
          params[:time] = DateTime.strptime(time_text, "%Y-%m-%d %I:%M %P")
        end

        return Entry.new(params)
      end

      parent_link = message_element.at_css('.link.commentparent').try(:at_css, 'a')
      if parent_link
        parent_href = parent_link[:href]
        parent_id = "cmt" + get_url_param(parent_href, "thread")
        @replies.each do |reply|
          params[:parent] = reply if reply.id == parent_id
        end
      else
        params[:parent] = @chapter.entry
      end

      if message_attributes.include?(:time)
        time_text = message_element.at_css('.datetime').text.strip
        params[:time] = DateTime.strptime(time_text, "%Y-%m-%d %I:%M %P (%Z)")
      end

      Comment.new(params)
    end
    def get_replies(chapter, options = {}, &block)
      return unless self.handles?(chapter)
      notify = options.fetch(:notify, true)

      return chapter.replies if already_processed(chapter, options, &block)

      pages = chapter.pages
      (LOG.error "Chapter (#{chapter.title}) has no pages" and return) if pages.blank?

      @chapter = chapter
      @replies = []
      @reply_ids = []
      if chapter.thread
        threadcmt = "cmt#{chapter.thread}"
        @reply_ids << threadcmt
        LOG.debug "Thread comment: \"#{threadcmt}\""
      else
        threadcmt = ''
        @reply_ids << -1 unless chapter.thread
      end

      pages.each do |page_url|
        @repeated_page_cache[@group_folder] ||= {}
        if @repeated_page_cache[@group_folder].key?(page_url)
          page = @repeated_page_cache[@group_folder][page_url][:page]
          comments = @repeated_page_cache[@group_folder][page_url][:comments]
        end

        page ||= get_undiscretioned(page_url, replace: false, where: @group_folder)
        unless page
          LOG.error "Page failed to load (discretion advised warning?)"
          break
        end
        page_content = page.at_css('#content')

        if @replies.empty?
          entry_element = page_content.at_css('.entry')
          entry = make_message(entry_element, message_attributes: message_attributes)
          chapter.entry = entry
        end
        page_no = get_url_param(page_url, 'page')

        comments ||= page_content.css('.comment-wrapper.full')
        if @page_list.include?(page_url)
          @repeated_page_cache[@group_folder][page_url] ||= {page: page, comments: comments}
        end
        comments.each do |comment|
          comment_element = comment.at_css('.comment')

          comment_link = comment_element.at_css('.link.commentpermalink').try(:at_css, 'a')
          comment_id = -1
          if comment_link
            comment_href = comment_link[:href]
            comment_id = "cmt" + get_url_param(comment_href, "thread")
          end

          parent_link = comment_element.at_css('.link.commentparent').try(:at_css, 'a')
          parent_id = -1
          if parent_link
            parent_href = parent_link[:href]
            parent_id = "cmt" + get_url_param(parent_href, "thread")
          end

          if (@reply_ids.include?(parent_id) or @reply_ids.include?(comment_id))
            reply = make_message(comment_element, message_attributes: message_attributes)
            if chapter.thread and reply.id == threadcmt
              LOG.debug "chapter.thread: '#{chapter.thread}'; reply.id: '#{reply.id}'; threadcmt: '#{threadcmt}'; comment_id: '#{comment_id}'; reply_ids.include?(comment_id): #{@reply_ids.include?(comment_id)}"
              LOG.debug "Found the chapter thread comment #{reply}. Setting its parent to the entry #{chapter.entry}."
              reply.parent = chapter.entry
            end
            reply.page_no = page_no if page_no
            @replies << reply
            @reply_ids << reply.id unless @reply_ids.include?(reply.id)
          end
        end
        @page_list << page_url
      end

      msg_str = "#{chapter.title}: parsed #{pages.length} page#{pages.length == 1 ? '' : 's'}"
      if block_given?
        yield msg_str
      elsif notify
        LOG.info msg_str
      end

      chapter.processed = message_attributes
      chapter.replies=@replies
    end
  end

  class ConstellationHandler < SiteHandler
    attr_reader :download_count
    def self.handles?(thing)
      return if thing.nil?
      return thing.unique_id.start_with?('constellation#') if thing.is_a?(GlowficEpub::Character)

      chapter_url = thing.url if thing.is_a?(GlowficEpub::Chapter)
      chapter_url ||= thing
      return if chapter_url.blank?

      uri = URI.parse(chapter_url)
      uri.host.end_with?("vast-journey-9935.herokuapp.com") || uri.host.end_with?("glowfic.com")
    end
    def initialize(options = {})
      super options
      # maps face_id or icon_id to face (without any "constellation#")
      @face_id_cache = {} # {"6951" => "[is a face: ahein, imgur..., etc.]"}
      # stores params used to generate faces, used in a from_json to update (map as above)
      @face_param_cache = {}
      # lists IDs that failed to update in get_updated_face
      @face_update_failures = []

      @character_id_cache = {}
      @character_param_cache = {}
      @char_page_cache = {}
      # When retrieved in get_face_by_id
      @moiety_cache = {}
      @char_user_map = {} # maps face_id => user_id
      @char_page_errors = [] # characters that have no icons
      @icon_errors = []
    end

    def get_permalink_for(message)
      if message.post_type == PostType::ENTRY
        "https://glowfic.com/posts/#{message.id}"
      else
        "https://glowfic.com/replies/#{message.id}#reply-#{message.id}"
      end
    end

    def get_full(chapter, options = {})
      [get_flat_page_for(chapter, options)]
    end

    def get_flat_page_for(chapter, options = {})
      params = {view: :flat}
      chapter_url = if chapter.is_a?(GlowficEpub::Chapter)
        chapter.url
      else
        chapter
      end

      return unless self.handles?(chapter_url)

      chapter.processed = false if chapter.is_a?(GlowficEpub::Chapter)

      chapter_url = set_url_params(clear_url_params(chapter_url), params)
      giri_or_cache(chapter_url, where: @group_folder)

      chapter_url
    end

    def check_webpage_accords_with_disk(page)
      # check the relevant data on the webpage is the same as the disk data, otherwise update disk data
      existed_disk = File.file?(get_page_location(page, where: @group_folder))

      page_web = giri_or_cache(page, where: 'temp')
      page_disk = giri_or_cache(page, replace: false, where: @group_folder)

      return false unless existed_disk

      # TODO: check that the flat page timestamps are the same (i.e. don't hardcode "different")
      return false
    end

    def check_cachepage_accords_with_disk(page, chapter)
      page_disk = giri_or_cache(page, replace: false, where: @group_folder)
      data_cache = chapter.check_page_data[page]
      page_cache = Nokogiri::HTML(data_cache) if data_cache

      chapter.check_page_data_set(page, page_disk)
      return false unless data_cache

      #  TODO: check that flat page timestamps are the same between cache and disk (i.e. don't hardcode "different")
      return false
    end

    def get_updated(chapter, options = {})
      return unless self.handles?(chapter)
      notify = options.fetch(:notify, true)
      chapter.url = standardize_chapter_url(chapter.url)

      # TODO: load stats page, check last time flat page was updated, check flat page timestamp, update if necessary

      is_new = true
      prev_pages = chapter.pages
      check_pages = chapter.check_pages
      if prev_pages.present?
        # check the check_pages for a difference
        is_new = false
        changed = false

        abort("Wrong number of check pages (#{check_pages.length}) for #{chapter}; update code. Check pages: #{check_pages}") unless check_pages.length == 1
        stats_page = check_pages.first

        changed = !check_webpage_accords_with_disk(stats_page)
        if changed
          LOG.debug "stats page doesn't accord between disk and site (#{stats_page})"
        else
          changed = !check_cachepage_accords_with_disk(stats_page)
          LOG.info "check page cache in JSON differed from old content, fixing (#{stats_page})" if changed
        end

        LOG.debug "check page #{stats_page} was not different" unless changed

        # TODO: check the flat page timestamp concurs? store it somewhere, check it against the check page timestamp.
        last_flat_timestamp = Time.now

        LOG.debug "#{'not ' unless changed}changed!"

        # check also if all the regular pages exist, in case someone deleted them
        pages_exist = true
        prev_pages.each_with_index do |page_url, i|
          page_loc = get_page_location(page_url, where: @group_folder)
          next if File.file?(page_loc)
          pages_exist = false
          LOG.error "Failed to find a file (page #{i}) for chapter #{chapter}. Will get again."
          break
        end

        # output if different & return if appropriate
        if changed
          LOG.debug "Content is different for #{chapter}"
        elsif pages_exist # (and not changed)
          msg_str = "#{chapter.title}: #{chapter.pages.length} page#{'s' unless chapter.pages.length == 1} (checked #{@download_count} page#{'s' unless @download_count == 1})"
          if block_given?
            yield msg_str
          elsif notify
            LOG.info msg_str
          end
          return chapter
        end
      end

      # Needs to be updated / hasn't been got
      chapter.processed = false

      chapter.pages = get_full(chapter, options)

      # reset chapter cache
      chapter.check_page_data = {}
      chapter.check_pages.each do |check_page|
        # use cached data (for speed) if already gathered this session:
        if has_cache?(check_page, where: 'temp')
          data_new = down_or_cache(check_page, where: 'temp')
          save_down(check_page, temp_data, where: @group_folder) # save into data_old
        end

        # set check_page_data for future
        chapter.check_page_data_set(check_page, down_or_cache(check_page, where: @group_folder))
      end

      # output as appropriate
      msg_str = "#{is_new ? 'New' : 'Updated'}: #{chapter.title}: #{chapter.pages.length} page#{'s' unless chapter.pages.length == 1} (Got #{@download_count} page#{'s' unless @download_count == 1})"
      if block_given?
        yield msg_str
      elsif notify
        LOG.info msg_str
      end
      return chapter
    end

    def get_moiety_by_id(character_id)
      char_page = giri_or_cache("https://glowfic.com/characters/#{character_id}/", replace: false)
      LOG.debug "nokogiri'd profile page"

      breadcrumb1 = char_page.at_css('.flash.subber a')
      if breadcrumb1 && breadcrumb1.text.strip == "Characters"
        user_info = char_page.at_css('#header #user-info')
        user_info.at_css('img').try(:remove)
        username = user_info.text.strip
      else
        username = breadcrumb1.text.split("Characters").first.strip
        username = username[0..-3] if username.end_with?("'s")
      end
      [username]
    end

    # fetches the user ID and username for the giripage, from the breadcrumbs
    def get_owner_from_breadcrumbs(giripage)
      subber = giripage.at_css('.flash.subber')
      breadcrumb = subber.at_css('a')
      if breadcrumb
        url = breadcrumb[:href]
        if url['users/']
          user_id = url.split('users/').last.split('/').first
          username = breadcrumb.text.strip
          return [user_id, username]
        end
      end
      user_link = giripage.at_css('#user-info').at_css('a')
      user_link.at_css('img').try(:remove)
      user_id = user_link.split('users/').last.split('/').first
      username = user_link.text.strip
      [user_id, username]
    end

    # returns face_id, icon_id, character_id bits from a face / face_id
    def fetch_face_id_parts(face)
      # TODO: make face ID standards clearer
      # starts with constellation# maybe?
      # can contain character ID
      # ends with icon ID (numeric or 'none')
      # e.g. {user#…}#none (user icon with no URL?)
      # e.g. {character_id}#{icon_id} (character's icon)
      # e.g. constellation#{icon_id} (not attached to a character)

      # TODO: also character ID standards
      # can have "user#" within? (at start?)
      # can start with "constellation#" but this is often stripped? … but also added.
      # *should* start with constellation#? but not for the cache? … but yes for the cache.
      # otherwise is numeric

      face_id = face.unique_id unless face.is_a?(String)
      face_id ||= face
      face_id = face_id.sub('constellation#', '') if face_id.start_with?('constellation#')
      icon_id = face_id.split('#').last
      character_id = face_id.sub("##{icon_id}", '')
      character_id = nil if character_id == face_id || character_id.blank?
      [face_id, icon_id, character_id]
    end

    def set_face_cache(face)
      face_id, icon_id, character_id = fetch_face_id_parts(face)
      @chapter_list.replace_face(face)

      @face_id_cache[icon_id] = face if face_id == icon_id
      @face_id_cache[face.unique_id] = face

      if character_id && @char_page_cache.key?(character_id)
        @char_page_cache[character_id][icon_id] = face
      end
      face
    end

    # fetches all faces in galleries attached to a character_id
    def get_faces_for_character(character_id)
      # TODO: handle user# characters?
      return if character_id.start_with?('user#')

      # skip errored pages
      return if @char_page_errors.include?(character_id)
      # return already-got data
      return @char_page_cache[character_id] if @char_page_cache.key?(character_id)

      # icon is from a character that has not yet been got nor errored

      char_page_url = "https://glowfic.com/characters/#{character_id}/"
      char_page = giri_or_cache(char_page_url)

      # fetch character's user ID
      user_id, _username = get_owner_from_breadcrumbs(char_page)
      unless user_id
        LOG.error "No user ID found on char page for #{character_id}"
      end
      @char_user_map[character_id] = user_id

      char_page_c = char_page.at_css("#content")
      icons = char_page_c.css(".gallery-icon")

      if icons.blank?
        LOG.error "No icons for character ##{character_id}."
        @char_page_errors << character_id
        return
      end

      character = get_character_by_id(character_id)

      icon_hash = {} # numeric_id => face
      default_icon = char_page_c.at_css('.character-icon')
      if default_icon
        icons << default_icon
      else
        LOG.warn "No default icon for character ID #{character_id}"
      end

      icons.each do |icon_element|
        icon_link = icon_element.at_css('a')
        icon_url = icon_link.try(:[], :href)
        icon_img = icon_link.at_css('img')
        icon_src = icon_img.try(:[], :src)

        (LOG.error "Failed to find an img URL on the icon page for character ##{character_id}"; next) if icon_src.blank?

        icon_keyword = icon_img.try(:[], :title)
        icon_id = icon_url.split("icons/").last if icon_url

        unless icon_id
          LOG.error "Failed to find an icon's numeric ID on character page ##{character_id}?"
          icon_id = "unknown"
        end

        params = {}
        params[:imageURL] = icon_src
        params[:character] = character
        params[:keyword] = icon_keyword
        params[:unique_id] = "#{character_id}##{icon_id}"
        params[:chapter_list] = @chapter_list
        face = Face.new(params)
        icon_hash[icon_id] = face
        @chapter_list.replace_face(face)
        if default_icon == icon_element
          icon_hash[:default] = face
          params[:character].default_face = face if params[:character] && !params[:character].default_face_id.present?
        end

        @face_id_cache[face.unique_id] = face
        @face_param_cache[face.unique_id] = params
      end
      LOG.debug "got #{icon_hash.keys.length} icon(s)"
      @char_page_cache[character_id] = icon_hash
    end

    # fetches a face for face_id from user_id's galleries for character_id (for ex-gallery icons)
    def get_face_for_user(desired_icon_id, user_id, character_id)
      usergal_page_url = "https://glowfic.com/users/#{user_id}/galleries/"
      usergal_page = giri_or_cache(usergal_page_url)
      LOG.debug "nokogiri'd"

      # TODO: could be made more efficient (find icons including the ID)
      character = get_character_by_id(character_id)
      icons = usergal_page.at_css('#content').css('.gallery-icon')
      face = nil
      icons.each do |icon_element|
        icon_link = icon_element.at_css('a')
        icon_url = icon_link.try(:[], :href)
        next unless icon_url
        icon_id = icon_url.split("icons/").last if icon_url
        next unless icon_id == desired_icon_id

        icon_img = icon_link.at_css('img')
        next unless icon_img
        icon_src = icon_img[:src]

        (LOG.error "Failed to find an img URL on the icon page for user ##{user_id}"; next) if icon_src.blank?

        icon_keyword = icon_img[:title]

        params = {}
        params[:imageURL] = icon_src
        params[:character] = character
        params[:keyword] = icon_keyword
        params[:unique_id] = "#{character_id}##{icon_id}"
        params[:chapter_list] = @chapter_list
        face = Face.new(params)

        @chapter_list.replace_face(face)
        @face_id_cache[face.unique_id] = face
        @face_param_cache[face.unique_id] = params

        LOG.debug "Found an icon for character #{character_id}: ID ##{icon_id} (on userpage ##{user_id})"
      end
      face
    end

    # fetches a face for icon_id from the icon itself (lacks character info)
    def get_face_for_icon(icon_id)
      icon_page = giri_or_cache("https://glowfic.com/icons/#{icon_id}/")
      LOG.debug "nokogiri'd"
      unless icon_page.at_css('#content').at_css('*')
        # check is for elements inside #content as .flash.error mysteriously doesn't show
        LOG.error "Encountered an error while trying to load icon ID #{icon_id}"
        return
      end

      icon_img = icon_page.at_css('#content').at_css('.icon-icon').try(:at_css, 'img')
      params = {}
      params[:imageURL] = icon_img.try(:[], :src)
      params[:keyword] = icon_img.try(:[], :title)
      params[:unique_id] = "constellation##{icon_id}"
      params[:chapter_list] = @chapter_list
      face = Face.new(params)
      @chapter_list.replace_face(face)
      @face_id_cache[icon_id] = face
      @face_param_cache[face.unique_id] = params
    end

    # fetches a face by ID
    def get_face_by_id(face_id, options={})
      try_chapterface = options.fetch(:try_chapterface, true)
      face_id, icon_id, character_id = fetch_face_id_parts(face_id)
      return @face_id_cache[face_id] if @face_id_cache.key?(face_id)
      return @face_id_cache[icon_id] if @face_id_cache.key?(icon_id) && character_id.blank?

      if try_chapterface
        chapter_face = @chapter_list.try(:get_face_by_id, face_id)
        if chapter_face.present?
          @face_id_cache[face_id] = chapter_face
          @face_id_cache[icon_id] ||= chapter_face
          return chapter_face
        end
      end

      character_id = nil if character_id == face_id || character_id.blank?

      # empty face for user
      if icon_id == "none"
        face_params = {}
        face_params[:imageURL] = nil
        face_params[:keyword] = "none"
        face_params[:unique_id] = "#{character_id}#none"
        face_params[:character] = get_character_by_id(character_id)
        face = Face.new(face_params)
        @chapter_list.replace_face(face)
        @face_param_cache[face.unique_id] = face_params
        @face_id_cache[face_id] = face
        return face
      end

      # get_icons_for_character
      if character_id && !character_id.start_with?("user#")
        get_faces_for_character(character_id)
      end
      return @face_id_cache[face_id] if @face_id_cache.key?(face_id)

      # get icons for user
      if character_id && @char_user_map.key?(character_id)
        get_face_for_user(icon_id, @char_user_map[character_id], character_id)
      end
      return @face_id_cache[face_id] if @face_id_cache.key?(face_id)

      get_face_for_icon(icon_id)
      return @face_id_cache[icon_id] if @face_id_cache.key?(icon_id)

      # Shouldn't ever occur? We just loaded the icon page;
      # it's probably going to error before this if there's no icon
      # or Face.new will complain about nil params?
      unless @icon_errors.include?(face_id)
        LOG.error "Failed to find a face for character: #{character_id} and icon: s#{icon_id}"
        @icon_errors << face_id
        nil
      end
    end

    # updates a face using a param_cache hash from the above methods
    def get_updated_face(face)
      return unless face
      return get_face_by_id(face.unique_id) if @face_param_cache.key?(face.unique_id)

      done_face = get_face_by_id(face.unique_id, try_chapterface: false)

      id = (done_face || face).unique_id
      face_hash = @face_param_cache[id] || @face_param_cache[id.sub('constellation#', '')]
      if face_hash.present?
        face.from_json! face_hash
      elsif done_face.present? && !@face_update_failures.include?(face.unique_id)
        LOG.error "Face was created, param cache was not set. Face not updating despite being supposed to. #{face}"
        @face_update_failures << face.unique_id
      end
      set_face_cache(face)
    end

    # ID cache uses:
    # constellation#user#{user_id} => character
    # constellation#{character_id} => character
    # i.e. character.unique_id => character
    def set_character_cache(character)
      @character_id_cache[character.unique_id] = character
    end

    # in each method below, user/character_id tries to be the numeric bit
    # and cache_id tries to be the unique_id as for the cache

    # get the character object for a user account
    def get_character_for_user(user_id)
      user_id = user_id.sub('constellation#', '') if user_id.start_with?('constellation#')
      user_id = user_id.sub('user#', '') if user_id.start_with?('user#')
      cache_id = "constellation#user##{user_id}"
      return @character_id_cache[cache_id] if @character_id_cache.key?(cache_id)

      user_page_url = "https://glowfic.com/users/#{user_id}/"
      user_page = giri_or_cache(user_page_url)
      LOG.debug "nokogiri'd"
      user_page_c = user_page.at_css('#content')
      char_name = user_page_c.at_css('th.centered').try(:text).try(:strip)

      params = {}
      params[:moiety] = char_name
      params[:name] = char_name
      params[:display] = char_name
      params[:unique_id] = cache_id

      character = Character.new(params)
      @character_id_cache[character.unique_id] = character
      @character_param_cache[character.unique_id] = params
      character
    end

    # get the character object for a constellation character
    def get_character_for_char(character_id)
      character_id = character_id.sub('constellation#', '') if character_id.start_with?('constellation#')
      cache_id = "constellation##{character_id}"
      return @character_id_cache[cache_id] if @character_id_cache.key?(cache_id)
      char_page_url = "https://glowfic.com/characters/#{character_id}/"
      char_page = giri_or_cache(char_page_url)
      LOG.debug "nokogiri'd"
      char_page_c = char_page.at_css('#content')

      char_screen = char_page_c.at_css(".character-screenname").try(:text).try(:strip)
      char_name = char_page_c.at_css(".character-name").try(:text).try(:strip)
      char_display = char_name
      char_display += " (#{char_screen})" unless char_screen.nil? || char_screen.downcase == char_name.downcase

      params = {}
      params[:moiety] = get_moiety_by_id(character_id)
      params[:name] = char_name
      params[:screenname] = char_screen
      params[:display] = char_display
      params[:unique_id] = cache_id

      character = Character.new(params)
      @character_id_cache[character.unique_id] = character
      @character_param_cache[character.unique_id] = params
      character
    end

    # get a constellation character by its ID (user/character account)
    def get_character_by_id(character_id, options={})
      # is given: user#{user_id} or {character_id} (by "make_message")
      character_id = character_id.sub("constellation#", "") if character_id.start_with?("constellation#")
      cache_id = "constellation##{character_id}"
      return @character_id_cache[cache_id] if @character_id_cache.key?(cache_id)

      try_chaptercharacter = options.fetch(:try_chaptercharacter, true)
      if try_chaptercharacter
        chapter_character = @chapter_list.try(:get_character_by_id, cache_id)
        if chapter_character.present?
          set_character_cache(chapter_character)
          return chapter_character
        end
      end

      if character_id.start_with?("user#")
        return get_character_for_user(character_id)
      else
        return get_character_for_char(character_id)
      end
    end

    # update a character by using a param_cache hash
    def get_updated_character(character)
      return unless character
      return get_character_by_id(character.unique_id) if @character_param_cache.key?(character.unique_id)

      get_character_by_id(character.unique_id, try_chaptercharacter: false)
      character_hash = @character_param_cache[character.unique_id]
      character.from_json! character_hash
      set_character_cache(character)
    end

    def make_message(message_element, options = {})
      # message_element is the ".post-container"
      message_attributes = options[:message_attributes] || msg_attrs

      Time.zone = 'Eastern Time (US & Canada)'

      message_anchor = message_element.at_css("> a[id*='reply-']")
      if message_anchor
        message_id = message_anchor[:id].split("reply-").last
        message_type = PostType::REPLY
      elsif message_element[:class].try(:[], /\bpost-reply\b/)
        LOG.error "Failed to find a reply's ID!"
      else
        # TODO: fix unnecessary re-processing of entry_title (see @entry_title)
        entry_title = message_element.parent.at_css('#post-title').try(:at_css, 'a')
        LOG.error "Couldn't find the post's title." unless entry_title

        message_id = entry_title[:href].split('posts/').last
        message_type = PostType::ENTRY
      end

      post_info_text = message_element.at_css('.post-info-text')
      author_element = post_info_text.at_css('.post-author').at_css('a')
      author_name = author_element.text.strip # FIXME: could be character alias
      author_id = author_element["href"].split("users/").last

      character_element = post_info_text.at_css('.post-character').try(:at_css, 'a')
      if character_element
        character_id = character_element["href"].split("characters/").last
        character_name = character_element.text.strip
        character_screen = post_info_text.at_css('.post-screenname').try(:text).try(:strip)
      else
        character_id = "user##{author_id}"
        character_name = nil
        character_screen = nil
      end
      character_display = character_name
      character_display += " (#{character_screen})" if character_name && character_screen

      date_element = message_element.at_css('> .post-footer')

      params = {}

      if message_attributes.include?(:time)
        create_date = date_element.at_css('.post-posted').try(:text).try(:strip)
        LOG.error "No create date for message ID ##{message_id}?" unless create_date
        if create_date
          params[:time] = Time.zone.parse(create_date).to_datetime
        end
      end
      if message_attributes.include?(:edittime)
        edit_date = date_element.at_css('.post-updated').try(:text).try(:strip)
        if edit_date
          params[:edittime] = Time.zone.parse(edit_date).to_datetime
        end
      end

      params[:content] = message_element.at_css('.post-content').inner_html.strip
      params[:character] = get_character_by_id(character_id) if message_attributes.include?(:character)
      params[:alias] = character_display if character_display && (params[:character].nil? || character_display != params[:character].display)
      params[:author_str] = author_name unless message_attributes.include?(:character)

      params[:id] = message_id
      params[:chapter] = @chapter

      if message_attributes.include?(:face)
        userpic = message_element.at_css('.post-icon').try(:at_css, 'img')
        icon_url = ''
        icon_name = 'none'
        icon_id = ''

        if userpic
          icon_id = userpic.parent[:href].split("icons/").last
          icon_url = userpic[:src]
          icon_name = userpic[:title]
        end

        if icon_id.present?
          if character_id == "user##{author_id}"
            face_id = "#{icon_id}"
          else
            face_id = "#{character_id}##{icon_id}"
          end

          if face_id.present?
            params[:face] = get_face_by_id(face_id)
            params[:face] ||= @chapter_list.get_face_by_id(face_id)
            LOG.error "could not get face for #{face_id} for message type #{message_type} ID #{message_id}" unless params[:face]
          end
        end

        if params[:face].nil?
          face_params = {}
          face_params[:keyword] = icon_name
          face_params[:character] = params[:character]
          face_params[:imageURL] = icon_url
          if icon_url.present?
            face_params[:unique_id] = icon_id
          else
            face_params[:unique_id] = "#{character_id}##{icon_name}"
          end
          face = Face.new(face_params)
          @chapter_list.add_face(face)
          params[:face] = face
        end
      end

      if message_type == PostType::ENTRY
        params[:entry_title] = @entry_title
        return @previous_message = Entry.new(params)
      end

      params[:parent] = @previous_message
      @previous_message = Comment.new(params)
    end

    def get_replies(chapter, options = {}, &block)
      return unless self.handles?(chapter)
      notify = options.fetch(:notify, true)

      return chapter.replies if already_processed(chapter, options, &block)

      pages = chapter.pages
      (LOG.error "Chapter (#{chapter.title}) has no pages"; return) if pages.blank?

      @entry_title = nil
      @chapter = chapter
      @replies = []
      @notify_extras = []
      pages.each do |page_url|
        page = giri_or_cache(page_url, replace: false, where: @group_folder)
        LOG.debug "nokogiri'd"

        error = page.at_css('.error.flash')
        if error
          error_text = error.text
          if error_text["do not have permission"]
            (LOG.error("Chapter '#{chapter.title}': Error. Page was private!"); break)
          elsif error_text["not be found"]
            (LOG.error("Chapter '#{chapter.title}': Error. Post does not exist!"); break)
          elsif error_text["content warning"]
            # is a content warning; save to ignore
          else
            (LOG.error("Chapter '#{chapter.title}': Error. Unknown post error: '#{error_text}'"); break)
          end
        end

        page_content = page.at_css('#content')
        post_title = page.at_css('#post-title')
        (LOG.error("No post title; probably not a post"); break) unless post_title
        @entry_title = post_title.text.strip unless @entry_title

        @chapter.title_extras = page.at_css('.post-subheader')&.text&.strip if @chapter.title_extras.blank?

        # process entry if replies blank
        if @replies.empty?
          @entry_element = page_content.at_css('.post-container.post-post')
          entry = make_message(@entry_element, message_attributes: message_attributes)
          chapter.entry = entry
        end

        # TODO: fix automatically fetching sections.
        # automatically fetch chapter sections if appropriate
        if page_url == pages.last && chapter.get_sections? && chapter.sections.blank?
          section_links = page.at_css('.flash.subber').css('a')
          sections = []
          section_links.each do |section_link|
            link_href = section_link[:href]
            # skip if blank, sandboxes, or "continuities"
            next if link_href.blank? || link_href[/\/boards(\/3)?\/?$/]
            # implement complex auto-gathering of IDs and sorting (later stripped)
            section_id = ''
            link_href = link_href[0..-2] if link_href.end_with?('/')
            section_id = 'AAAA-' + link_href.split('boards/').last if link_href['boards/']
            section_id = 'AAAB-' + link_href.split('board_sections/').last if link_href['board_sections/']
            section_id ||= 'AAAC-' + link_href.split('/').last
            sections << section_id + '-' + section_link.text.strip
          end
          chapter.sections = sections
        end

        comments = page_content.css('> .post-container.post-reply')
        comments.each do |comment_element|
          reply = make_message(comment_element, message_attributes: message_attributes)
          @replies << reply
        end

        # check the page status with enders
        # TODO: fix automatically fetching post enders
        if page_url == pages.last
          post_ender = page_content.at_css('.post-ender')
          if post_ender
            things = [chapter.entry] + @replies
            last_time = things.last.try(:time)
            ender_text = post_ender.text.downcase
            # TODO: sanity check if the "old_time &&" is necessary
            # TODO: sanity check if time_hiatus should override time_abandoned like time_completed, vice versa
            if !last_time
              LOG.error "#{chapter.title}: ended but cannot get last_time."
            elsif ender_text['ends'] || ender_text['complete']
              old_time = chapter.time_completed
              chapter.time_completed = last_time

              str = "completed on '#{date_display(chapter.time_completed)}'"
              str += " (old time: #{date_display(old_time)})" if old_time && old_time != chapter.time_completed
              @notify_extras << str
            elsif ender_text['hiatus']
              old_time = chapter.time_hiatus
              # reset time_completed, save time_hiatus (if newer or only existent)
              if chapter.time_completed.nil? || last_time >= chapter.time_completed
                chapter.time_hiatus = last_time
                chapter.time_completed = nil
              end

              str = "hiatus on #{date_display(chapter.time_hiatus)}"
              str += " (old time: #{date_display(old_time)})" if old_time && old_time != chapter.time_hiatus
              @notify_extras << str
            elsif ender_text['abandon']
              old_time = chapter.time_abandoned
              # reset time_completed, save time_abandoned (if newer or only existent)
              if chapter.time_completed.nil? || last_time >= chapter.time_completed
                chapter.time_abandoned = last_time
                chapter.time_completed = nil
              end

              str = "abandoned on #{date_display(chapter.time_abandoned)}"
              str += " (old time: #{date_display(old_time)})" if old_time && old_time != chapter.time_abandoned
              @notify_extras << str
            else
              LOG.error "#{chapter.title}: ended non-hiatus non-complete non-abandoned on #{date_display(last_time)} (???)"
            end
          elsif chapter.time_completed || chapter.time_hiatus || chapter.time_abandoned
            @notify_extras << "no ender; wiping time_* statuses." +
              (chapter.time_completed ? " completed #{date_display(chapter.time_completed)}" : '') +
              (chapter.time_hiatus ? " hiatus #{date_display(chapter.time_hiatus)}" : '') +
              (chapter.time_abandoned ? " abandoned #{date_display(chapter.time_abandoned)}" : '')
            chapter.time_completed = nil
            chapter.time_hiatus = nil
            chapter.time_abandoned = nil
          end
        end
      end

      pages_effectual = (@replies.length / 25.0).ceil
      pages_effectual = 1 if pages_effectual < 1

      msg_str = "#{chapter.title}: parsed #{pages_effectual} page#{'s' unless pages_effectual == 1}"
      msg_str += ", #{@notify_extras * ', '}" if @notify_extras.present?
      if block_given?
        yield msg_str
      elsif notify
        LOG.info msg_str
      end
      chapter.processed = message_attributes
      chapter.replies = @replies
    end
  end
end
