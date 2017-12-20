class StubHandler < GlowficIndexHandlers::IndexHandler
  handles :thing, :thingtwo # does not handle :other_thing
end

RSpec.describe GlowficIndexHandlers do
  describe 'get_handler_for' do
    it 'returns handler if match is found' do
      expect(GlowficIndexHandlers.get_handler_for(:constellation)).to eq(GlowficIndexHandlers::ConstellationIndexHandler)
    end

    it 'returns empty if no match' do
      expect(GlowficIndexHandlers.get_handler_for(:nonexistent)).to be_blank
    end
  end

  describe GlowficIndexHandlers::IndexHandler do
    describe "handles?" do
      it "is true for given items" do
        expect(StubHandler.handles?(:thing)).to eq(true)
        expect(StubHandler.handles?(:thingtwo)).to eq(true)
      end

      it "is false for other items" do
        expect(StubHandler.handles?(:other_thing)).to eq(false)
      end
    end

    describe "#chapter_list" do
      it "creates a new chapter list if none exists" do
        handler = StubHandler.new
        expect(handler.chapter_list).to be_a(GlowficEpub::Chapters)
      end

      it "uses extant chapter list if given one" do
        list = GlowficEpub::Chapters.new
        handler = StubHandler.new(chapter_list: list)
        expect(handler.chapter_list).to eq(list)
      end
    end

    describe "#persist_chapter_data" do
      skip "has more tests"
    end

    describe "#get_chapter_titles" do
      skip "has more tests"
    end

    describe "#chapter_from_toc" do
      it "works with simple dreamwidth example" do
        handler = StubHandler.new
        data = {
          url: 'https://exampleblog.dreamwidth.org/1234.html?thread=9876',
          title: 'test'
        }

        expect(handler).to receive(:persist_chapter_data)
        response = handler.chapter_from_toc(data)

        expect(response.title).to eq('test')
        expect(response.url).to eq('https://exampleblog.dreamwidth.org/1234.html?style=site&thread=9876')
        expect(response.thread).to eq('9876')
      end

      it "works with simple constellation example" do
        handler = StubHandler.new
        data = {
          url: 'https://glowfic.com/posts/123',
          title: 'test'
        }

        expect(handler).to receive(:persist_chapter_data)
        response = handler.chapter_from_toc(data)

        expect(response.title).to eq('test')
        expect(response.url).to eq('https://glowfic.com/posts/123')
        expect(response.thread).to be_nil
      end

      skip "has more tests"
    end
  end

  describe GlowficIndexHandlers::CommunityHandler do
    skip "has more tests"
  end

  describe GlowficIndexHandlers::OrderedListHandler do
    skip "has more tests"
  end

  describe GlowficIndexHandlers::SandboxListHandler do
    skip "has more tests"
  end

  describe GlowficIndexHandlers::NeatListHandler do
    skip "has more tests"
  end
end
