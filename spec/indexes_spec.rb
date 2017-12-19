require 'handlers_indexes'

class StubHandler < GlowficIndexHandlers::IndexHandler
  handles :thing, :thingtwo # does not handle :other_thing
end

RSpec.describe GlowficIndexHandlers do
  include ScraperUtils
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

  describe GlowficIndexHandlers::ConstellationIndexHandler do
    let(:handler) { GlowficIndexHandlers::ConstellationIndexHandler.new }

    describe "#fix_url_folder" do
      it "does nothing to normal URLs" do
        prev = 'https://glowfic.com/replies/1234#reply-1234'
        post = prev
        expect(handler.fix_url_folder(prev)).to eq(post)
      end

      it "adds trailing slash to relevant folders" do
        prev = 'https://glowfic.com/users/123'
        post = prev + '/'
        expect(handler.fix_url_folder(prev)).to eq(post)
      end

      it "handles special characters after the ID code" do
        prev = 'https://glowfic.com/users/123?view=galleries'
        post = 'https://glowfic.com/users/123/?view=galleries'
        expect(handler.fix_url_folder(prev)).to eq(post)

        prev = 'https://glowfic.com/users/123#'
        post = 'https://glowfic.com/users/123/#'
        expect(handler.fix_url_folder(prev)).to eq(post)
      end
    end

    describe "#get_absolute_url" do
      it "handles relative root URLs" do
        url_path = '/boards'
        current_url = 'https://glowfic.com/replies/1234#reply-1234'
        expect(handler.get_absolute_url(url_path, current_url)).to eq('https://glowfic.com/boards')
      end

      it "handles relative non-root URLs" do
        url_path = '1235'
        current_url = 'https://glowfic.com/replies/1234#reply-1234'
        expect(handler.get_absolute_url(url_path, current_url)).to eq('https://glowfic.com/replies/1235')
      end

      it "handles absolute URLs" do
        url_path = 'https://example.com/'
        current_url = 'https://glowfic.com/replies/1234#reply-1234'
        expect(handler.get_absolute_url(url_path, current_url)).to eq('https://example.com/')
      end
    end

    describe "#board_to_block" do
      skip "has more tests"
    end
    describe "#userlist_to_block" do
      skip "has more tests"
    end
    describe "#toc_to_chapterlist" do
      skip "has more tests"
    end

    skip "has more tests"
  end

  describe GlowficIndexHandlers::TestIndexHandler do
    it "handles test index properly" do
      handler = GlowficIndexHandlers::TestIndexHandler.new(group: :test)
      # TODO: check sections, despite sorting
      const = GlowficIndexHandlers::INDEX_PRESETS[:test].map do |item|
        {
          url: standardize_chapter_url(item[:url]),
          title: item[:title],
          # sections: item[:sections],
          marked_complete: item[:marked_complete]
        }
      end
      data = []
      list = handler.toc_to_chapterlist do |detail|
        data << {
          url: detail.url,
          title: detail.title,
          # sections: detail.sections,
          marked_complete: detail.marked_complete
        }
      end
      expect(const).to eq(data)
      # expect(list)
    end

    skip "handles report index properly"
    skip "handles mwf indexes properly"

    skip "has more tests"
  end
end
