RSpec.describe GlowficSiteHandlers::ConstellationHandler do
  Handler = GlowficSiteHandlers::ConstellationHandler
  let(:handler) { Handler.new(group: :example) }

  def create(thing, **kwargs)
    @post_id ||= 0
    if thing == :chapter
      @post_id += 1
      kwargs[:url] = "https://glowfic.com/posts/#{@post_id}" unless kwargs.key?(:url)
      kwargs[:title] = "Post #{@post_id}" unless kwargs.key?(:title)
      Chapter.new(**kwargs)
    elsif thing == :entry
      kwargs[:chapter] = create(:chapter) unless kwargs.key?(:chapter)
      Entry.new(**kwargs)
    elsif thing == :comment
      kwargs[:chapter] = create(:chapter) unless kwargs.key?(:chapter)
      Comment.new(**kwargs)
    else
      abort("Unrecognized thing to create: #{thing}")
    end
  end

  describe "handles?" do
    it "does not handle nil" do
      expect(Handler.handles?(nil)).to be_falsy
    end

    it "handles constellation chapters"
    it "does not handle non-constellation chapters"

    it "does not handle blank URLs" do
      expect(Handler.handles?('')).to be_falsy
    end

    it "handles constellation URLs" do
      expect(Handler.handles?('https://glowfic.com/posts/1')).to eq(true)
      expect(Handler.handles?('https://www.glowfic.com/posts/1')).to eq(true)
    end

    it "does not handle non-constellation URLs" do
      expect(Handler.handles?('https://alicornutopia.dreamwidth.org/1640.html')).to eq(false)
    end
  end

  describe "#get_permalink_for" do
    it "gets right URL for post" do
      entry = create(:entry, content: '', id: '9876')
      expect(handler.get_permalink_for(entry)).to eq('https://glowfic.com/posts/9876')
    end

    it "gets right URL for reply" do
      reply = create(:comment, content: '', id: '9876')
      expect(handler.get_permalink_for(reply)).to eq('https://glowfic.com/replies/9876#reply-9876')
    end

    it "does something good with neither"
  end

  describe "#get_full" do
    it "calls get_flat_page_for" do
      chapter = double
      options = {thing: :other}
      expect(handler).to receive(:get_flat_page_for).with(chapter, options)

      handler.get_full(chapter, options)
    end

    it "returns flat page array" do
      expect(handler).to receive(:get_flat_page_for).and_return('https://glowfic.com/posts/1?view=flat')

      expect(handler.get_full(nil)).to eq(['https://glowfic.com/posts/1?view=flat'])
    end
  end

  describe "#get_flat_page_for" do
    it "attempts to download flat mode" do
      expect(handler).to receive(:giri_or_cache).with('https://glowfic.com/posts/1?view=flat', where: 'web_cache/example')
      handler.get_flat_page_for('https://glowfic.com/posts/1')
    end

    it "does not proceed if it doesn't handle the chapter" do
      expect(handler).not_to receive(:giri_or_cache)
      handler.get_flat_page_for('https://dreamwidth.org/')
    end
  end

  describe "#check_webpage_accords_with_disk"

  describe "#check_cachepage_accords_with_disk"

  describe "#get_updated" do
    it "downloads all pages for a new chapter" do
      chapter = create(:chapter)
      allow(chapter).to receive(:url=).with('https://glowfic.com/posts/1')

      expect(LOG).to receive(:info).with("New: #{chapter.title}: 1 page (Got 0 pages)")

      expect(handler).to receive(:get_flat_page_for).with(chapter, {}).and_return('https://glowfic.com/posts/1?view=flat')
      allow(handler).to receive(:down_or_cache).with('https://glowfic.com/posts/1/stats', where: 'web_cache/example').and_return('data')

      expect(chapter).to receive(:processed=).with(false).and_call_original
      expect(chapter).to receive(:pages=).with(['https://glowfic.com/posts/1?view=flat']).and_call_original
      expect(chapter).to receive(:check_page_data=).with({}).and_call_original
      expect(chapter).to receive(:check_page_data_set).with('https://glowfic.com/posts/1/stats', 'data')

      handler.get_updated(chapter)
    end

    it "checks last few pages rather than using a ton of bandwidth and processing time for unchanged files"
    it "checks if chapter is out of sync with cached file is out of sync with site"
    it "downloads all relevant pages (flat mode)" # FIXME: see above
    it "saves relevant check pages"
    # it "outputs chapter length"
  end

  describe "#get_moiety_by_id"

  describe "#get_owner_from_breadcrumbs"

  describe "#fetch_face_id_parts"
  describe "#set_face_cache"
  describe "#get_faces_for_character"
  describe "#get_face_for_user"
  describe "#get_face_for_icon"
  describe "#get_face_by_id"
  describe "#get_updated_face"

  describe "#set_character_cache"
  describe "#get_character_for_user"
  describe "#get_character_for_char"
  describe "#get_character_by_id"
  describe "#get_updated_character"

  describe "#make_message" do
    it "works for posts"
    it "works for replies"
    it "has more tests"
  end

  describe "#get_replies" do
    it "uses downloaded pages"
    it "works on a short post"
    it "works on a long post"
    it "works in various error cases (private, non existent, content warnings, other errors)"
    it "gets status from post ender"
    it "deals with old statuses being overridden / removed"
    it "figures out thread sections when necessary"
  end
end
