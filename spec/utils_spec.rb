require 'scraper_utils'

class UtilModule
  extend ScraperUtils
end

RSpec.describe ScraperUtils do
  describe ScraperUtils::FileLogIO do
    skip "has more tests"
  end

  describe ScraperUtils::LOG do
    skip "has more tests"
  end

  describe "get_page_location" do
    def get_page_location(*args, **kwargs)
      UtilModule.get_page_location(*args, **kwargs)
    end

    it "returns nil for non-http URLs" do
      expect(get_page_location('ftp://example.com')).to be_nil
    end

    it "places simple URLs correctly" do
      expect(get_page_location('https://example.com/page')).to eq('web_cache/example.com/page')
    end

    it "places foldered URLs correctly" do
      expect(get_page_location('https://example.com/folder/to/file.html')).to eq('web_cache/example.com/folder/to/file.html')
    end

    it "handles query parameters correctly" do
      expect(get_page_location('https://example.com/page?test=blah')).to eq('web_cache/example.com/page~QMARK~test=blah')

      expected = 'web_cache/example.com/page~QMARK~stuff=thing&test=blah'
      expect(get_page_location('https://example.com/page?test=blah&stuff=thing')).to eq(expected)
      expect(get_page_location('https://example.com/page?stuff=thing&test=blah')).to eq(expected)
    end

    it "handles index files correctly" do
      expect(get_page_location('https://example.com/folder/')).to eq('web_cache/example.com/folder/index')

      expect(get_page_location('https://example.com/folder/?param=thing')).to eq('web_cache/example.com/folder/index~QMARK~param=thing')
    end

    it "accepts 'where' param to change folder location" do
      expect(get_page_location('https://example.com/test/file.html?thing=blah&stuff=asdf', where: 'another_folder/thing')).to eq('another_folder/thing/example.com/test/file.html~QMARK~stuff=asdf&thing=blah')
    end
  end
end
