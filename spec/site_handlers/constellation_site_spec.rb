RSpec.describe GlowficSiteHandlers::ConstellationHandler do
  Handler = GlowficSiteHandlers::ConstellationHandler
  let(:handler) { Handler.new }

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
    def create_entry(**kwargs)
      Entry.new(**kwargs)
    end

    def create_reply(**kwargs)
      Comment.new(**kwargs)
    end

    it "gets right URL for post" do
      entry = create_entry(content: '', chapter: nil, id: '9876')
      expect(handler.get_permalink_for(entry)).to eq('https://glowfic.com/posts/9876')
    end

    it "gets right URL for reply" do
      reply = create_reply(content: '', chapter: nil, id: '9876')
      expect(handler.get_permalink_for(reply)).to eq('https://glowfic.com/replies/9876#reply-9876')
    end

    it "does something good with neither"
  end

  describe "#get_full" do
    it "uses get_some because for some reason" # TODO: why? what do these names mean?
  end

  describe "#get_flat_page_for" do
    it "uses flat mode" # FIXME: do this
    it "does not proceed if it doesn't handle the chapter"
    it "downloads each relevant page"
  end

  describe "#check_webpage_accords_with_disk"

  describe "#check_cachepage_accords_with_disk"

  describe "#get_updated" do
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
