class StubSiteHandler < GlowficSiteHandlers::SiteHandler
end

RSpec.describe GlowficSiteHandlers do
  describe 'get_handler_for' do
    it 'returns handler if URL match is found' do
      expect(GlowficSiteHandlers.get_handler_for('https://glowfic.com/posts/1')).to eq(GlowficSiteHandlers::ConstellationHandler)
    end

    it 'returns handler if chapter match is found'

    it 'returns empty if no match' do
      expect(GlowficSiteHandlers.get_handler_for('https://example.com/')).to be_blank
      # TODO: add chapter fail to match
    end
  end

  describe GlowficSiteHandlers::SiteHandler do
    describe "handles?" do
      it "handles no URLs" do
        expect(StubSiteHandler.handles?('https://example.com/')).to eq(false)
        expect(StubSiteHandler.handles?('https://glowfic.com/posts/1')).to eq(false)
      end

      it "handles no chapters"
    end
    describe "#handles?" do
      it "calls the class method"
    end

    it "initializes as expected"

    describe "#message_attributes" do
      describe "when calculating" do
        it "defaults to msg_attrs"
        it "blacklists"
        it "whitelists"
        it "rejects both a white- and black-list"
      end
      describe "when requesting" do
        it "hands previous data given"
      end
    end

    describe "#already_processed" do
      it "can figure out from message_attributes and a chapter if everything is processed"
      it "assumes not if no replies"
    end

    describe "#down_or_cache" do
      it "uses cache if present"
      it "downloads if not cached"
      it "can be overridden not to use cache"
    end

    describe "#giri_or_cache" do
      it "uses parse cache if present"
      it "uses download cache if present"
      it "downloads if not cached"
      it "can be overridden not to use cache"
    end

    # TODO: get_updated, remove_cache, remove_giri_cache, has_cache?, save_down, msg_attrs

    it "has more tests"
  end

  describe GlowficSiteHandlers::DreamwidthHandler do
    skip "has more tests"
  end

  it "has more tests"
end
