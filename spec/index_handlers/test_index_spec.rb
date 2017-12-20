RSpec.describe GlowficIndexHandlers::TestIndexHandler do
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
