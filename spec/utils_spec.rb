class UtilModule
  extend ScraperUtils
end

RSpec.describe ScraperUtils do
  describe ScraperUtils::FileLogIO do
    it "writes to given file" do
      Dir.mktmpdir do |dir|
        file_log = FileLogIO.new('file.log', dir)
        file_log.write('text')
        file_log.close
        expect(File.open(File.join(dir, 'file.log'), 'r').read).to eq('text')
      end
    end

    skip "has more tests"
  end

  describe ScraperUtils::LOG do
    skip "has more tests"
  end

  describe "get_page_location" do
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

  describe "#download_file" do
    skip "has more tests"
  end

  describe "#get_page" do
    skip "has more tests"
  end

  describe "#get_page_data" do
    skip "has more tests"
  end

  describe "#get_text_on_line" do
    skip "has more tests"
  end

  describe "#standardize_chapter_url" do
    it "leaves good URLs intact" do
      expect(standardize_chapter_url('https://glowfic.com/posts/123')).to eq('https://glowfic.com/posts/123')
      expect(standardize_chapter_url('https://testblog.dreamwidth.org/1234.html?style=site')).to eq('https://testblog.dreamwidth.org/1234.html?style=site')
    end

    it "cleans fragments" do
      expect(standardize_chapter_url('https://example.com/#blah')).to eq('https://example.com/')
    end

    it "cleans dreamwidth URL params" do
      expect(standardize_chapter_url('https://testblog.dreamwidth.org/1234.html')).to eq('https://testblog.dreamwidth.org/1234.html?style=site')
      expect(standardize_chapter_url('https://testblog.dreamwidth.org/1234.html?thread=9876&test=other')).to eq('https://testblog.dreamwidth.org/1234.html?style=site&thread=9876')
    end

    it "cleans constellation URL params" do
      expect(standardize_chapter_url('https://glowfic.com/posts/1234?page=5&per_page=50')).to eq('https://glowfic.com/posts/1234')
    end

    skip "has more tests"
  end

  describe "#standardize_params" do
    it "mutates hashes to have symbol keys" do
      expect(standardize_params({thing: 'blah1', 2 => 'blah2', 'test' => 'blah3'})).to eq({thing: 'blah1', 2 => 'blah2', test: 'blah3'})
    end
  end

  describe "#sort_query" do
    it "returns nil if given blank" do
      expect(sort_query(nil)).to be_nil
      expect(sort_query('')).to be_nil
    end

    it "orders query params" do
      expect(sort_query('thing1=a&thing2=b')).to eq('thing1=a&thing2=b')
      expect(sort_query('thing2=b&thing1=a')).to eq('thing1=a&thing2=b')
      expect(sort_query('a=blah&b=test&c=amazing&d=solitude')).to eq('a=blah&b=test&c=amazing&d=solitude')
    end
    skip "has more tests"
  end
end

RSpec.describe GlowficEpub do
  describe "build_moieties" do
    skip "has more tests"
  end
end
