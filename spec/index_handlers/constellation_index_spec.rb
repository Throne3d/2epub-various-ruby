RSpec.describe GlowficIndexHandlers::ConstellationIndexHandler do
  let(:handler) { GlowficIndexHandlers::ConstellationIndexHandler.new(group: :example) }

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

      prev = 'https://glowfic.com/users'
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

      prev = 'https://glowfic.com/users#'
      post = 'https://glowfic.com/users/#'
      expect(handler.fix_url_folder(prev)).to eq(post)
    end
  end

  describe "#get_absolute_url" do
    it "handles relative root URLs" do
      url_path = '/boards/'
      current_url = 'https://glowfic.com/replies/1234#reply-1234'
      expect(handler.get_absolute_url(url_path, current_url)).to eq('https://glowfic.com/boards/')
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
    def check_function(url, expected, params={})
      chapters = []
      handler.board_to_block(params.merge(board_url: url)) do |chapter|
        chapters << {url: chapter.url, title: chapter.title, sections: chapter.sections}
      end
      expect(chapters).to eq(expected)
    end

    def stub_local(file, url)
      stub_request(:get, url).to_return(status: 200, body: File.new('spec/fixtures/indexes/constellation-board-' + file + '.html'))
    end

    before(:each) do
      allow(STDOUT).to receive(:puts)
      allow(LOG).to receive(:info)
    end

    # sectioned
    it "succeeds with a sectioned board" do
      url = 'https://glowfic.com/boards/1'
      file = 'sectioned'
      expected = [
        {
          url: 'https://glowfic.com/posts/5',
          title: 'Post1',
          sections: ['Sectioned board', 'Nonempty section']
        },
        {
          url: 'https://glowfic.com/posts/3',
          title: 'Post2',
          sections: ['Sectioned board', 'Nonempty section 2']
        },
        {
          url: 'https://glowfic.com/posts/4',
          title: 'Post3',
          sections: ['Sectioned board', 'Nonempty section 2']
        }
      ]

      stub_local(file, url + '/')
      check_function(url, expected)
    end

    # sectioned_with_unsectioned_posts
    it "succeeds with a sectioned board with unsectioned posts" do
      url = 'https://glowfic.com/boards/2'
      file = 'sectioned_with_unsectioned_posts'
      expected = [
        {
          url: 'https://glowfic.com/posts/5',
          title: 'Post1',
          sections: ['Sectioned board with unsectioned posts', 'Nonempty section']
        },
        {
          url: 'https://glowfic.com/posts/3',
          title: 'Post2',
          sections: ['Sectioned board with unsectioned posts', 'Nonempty section 2']
        },
        {
          url: 'https://glowfic.com/posts/4',
          title: 'Post3',
          sections: ['Sectioned board with unsectioned posts', 'Nonempty section 2']
        },
        {
          url: 'https://glowfic.com/posts/6',
          title: 'Post4',
          sections: ['Sectioned board with unsectioned posts']
        },
        {
          url: 'https://glowfic.com/posts/7',
          title: 'Post5',
          sections: ['Sectioned board with unsectioned posts']
        }
      ]

      stub_local(file, url + '/')
      check_function(url, expected)
    end

    # unsectioned_short
    it "succeeds with a one-page unsectioned board" do
      url = 'https://glowfic.com/boards/3'
      file = 'unsectioned_short'
      expected = [
        {
          url: 'https://glowfic.com/posts/5',
          title: 'Post1',
          sections: ['Short unsectioned board']
        },
        {
          url: 'https://glowfic.com/posts/4',
          title: 'Post3',
          sections: ['Short unsectioned board']
        },
        {
          url: 'https://glowfic.com/posts/3',
          title: 'Post2',
          sections: ['Short unsectioned board']
        },
        {
          url: 'https://glowfic.com/posts/7',
          title: 'Post5',
          sections: ['Short unsectioned board']
        },
        {
          url: 'https://glowfic.com/posts/6',
          title: 'Post4',
          sections: ['Short unsectioned board']
        }
      ]

      stub_local(file, url + '/')
      check_function(url, expected)
    end

    # unsectioned_long_{1,2}
    it "succeeds with a many-page unsectioned board" do
      url = 'https://glowfic.com/boards/4'
      expected = []
      1.upto(26) do |i|
        expected << {
          url: "https://glowfic.com/posts/#{i+2}",
          title: "Post#{i}",
          sections: ['Long unsectioned board']
        }
      end

      stub_local('unsectioned_long_1', url + '/')
      stub_local('unsectioned_long_2', url + '/?page=2')
      check_function(url, expected)
    end

    # reversed_long_{1,2}
    it "succeeds with a many-page reverse-order boards when told to reverse" do
      url = 'https://glowfic.com/boards/9'
      expected = []
      1.upto(26) do |i|
        expected << {
          url: "https://glowfic.com/posts/#{i+2}",
          title: "Post#{i}",
          sections: ['Long unsectioned reversed board']
        }
      end

      stub_local('reversed_long_1', url + '/')
      stub_local('reversed_long_2', url + '/?page=2')
      check_function(url, expected, reverse: true)
    end

    # empty
    it "succeeds with an empty board" do
      url = 'https://glowfic.com/boards/5'
      file = 'empty'
      expected = []

      stub_local(file, url + '/')
      check_function(url, expected)
    end

    # sectioned_with_empty
    it "succeeds with a board with an empty section" do
      url = 'https://glowfic.com/boards/6'
      file = 'sectioned_with_empty'
      expected = [
        {
          url: 'https://glowfic.com/posts/5',
          title: 'Post1',
          sections: ['Sectioned board with empty section', 'Nonempty section']
        },
        {
          url: 'https://glowfic.com/posts/6',
          title: 'Post4',
          sections: ['Sectioned board with empty section']
        },
        {
          url: 'https://glowfic.com/posts/7',
          title: 'Post5',
          sections: ['Sectioned board with empty section']
        },
        {
          url: 'https://glowfic.com/posts/3',
          title: 'Post2',
          sections: ['Sectioned board with empty section']
        },
        {
          url: 'https://glowfic.com/posts/4',
          title: 'Post3',
          sections: ['Sectioned board with empty section']
        }
      ]

      stub_local(file, url + '/')
      check_function(url, expected)
    end

    # described
    it "succeeds with a board with a description" do
      url = 'https://glowfic.com/boards/7'
      file = 'described'
      expected = [
        {
          url: 'https://glowfic.com/posts/5',
          title: 'Post1',
          sections: ['Described board', 'Nonempty section']
        },
        {
          url: 'https://glowfic.com/posts/3',
          title: 'Post2',
          sections: ['Described board', 'Nonempty section 2']
        },
        {
          url: 'https://glowfic.com/posts/4',
          title: 'Post3',
          sections: ['Described board', 'Nonempty section 2']
        }
      ]

      stub_local(file, url + '/')
      check_function(url, expected)
    end

    # timestamped
    it "pays attention to given 'before' and 'after' times" do
      url = 'https://glowfic.com/boards/8'
      file = 'timestamped'
      expected = [
        { # Dec 19, 2017  7:25 PM
          url: 'https://glowfic.com/posts/31',
          title: 'Post3',
          sections: ['Board with careful timestamps']
        },
        { # Dec 19, 2016  7:25 PM
          url: 'https://glowfic.com/posts/30',
          title: 'Post2',
          sections: ['Board with careful timestamps']
        },
        { # Dec 19, 2015  7:25 PM
          url: 'https://glowfic.com/posts/29',
          title: 'Post1',
          sections: ['Board with careful timestamps']
        }
      ]

      zone = ActiveSupport::TimeZone['America/New_York']

      stub_local(file, url + '/')
      check_function(url, expected)
      check_function(url, expected, after: zone.local(2015), before: zone.local(2018))

      check_function(url, expected[0..-2], after: zone.local(2016))
      check_function(url, expected[0..-3], after: zone.local(2017))
      check_function(url, [], after: zone.local(2018))

      check_function(url, expected[1..-1], before: zone.local(2017))
      check_function(url, expected[2..-1], before: zone.local(2016))
      check_function(url, [], before: zone.local(2015))

      check_function(url, expected[0..0], after: zone.local(2017, 12, 19, 19, 24), before: zone.local(2017, 12, 19, 19, 26))
      check_function(url, [], after: zone.local(2017, 12, 19, 19, 26), before: zone.local(2018))
      check_function(url, [], after: zone.local(2017), before: zone.local(2017, 12, 19, 19, 24))
    end
  end

  describe "#userlist_to_block" do
    skip "has more tests"
  end

  describe "#toc_to_chapterlist" do
    let(:stubbed_chapter_list) { double }

    def stub_chapter_list
      allow(handler).to receive(:chapter_list).and_return(stubbed_chapter_list)
    end

    Obj = Struct.new(:id, :board_id)

    def new_chapter(board_id=nil)
      @i ||= 0
      @i += 1
      Obj.new(@i, board_id)
    end

    it "rejects unrecognized URLs" do
      expect do
        handler.toc_to_chapterlist(fic_toc_url: 'https://glowfic.com/')
      end.to raise_error(ArgumentError, "URL is not an accepted format – failed")
    end

    context "for boards list" do
      def stub_local(file, url)
        stub_request(:get, url).to_return(status: 200, body: File.new('spec/fixtures/indexes/constellation-boards-' + file + '.html'))
      end

      before(:each) do
        allow(STDOUT).to receive(:puts)
        allow(LOG).to receive(:info)
        stub_chapter_list
      end

      BOARDS_URL = 'https://glowfic.com/boards'

      def test_yields(handler, expected_params, count, params={})
        expected_chapters = [] # filled, each time board_to_block is called, with one new chapter
        given_params = [] # stores params board_to_block is called with, to compare to actual board URLs from HTML
        given_chapters = [] # stores chapters sent to the chapter list, to compare to chapters created
        yielded_chapters = [] # stores chapters yielded to a block on toc_to_chapterlist, to compare to chapters created

        # stub board_to_block, and yield one fake chapter for each board
        expect(handler).to receive(:board_to_block).exactly(count).times do |params, &block|
          given_params << params

          board_url = params[:board_url]
          board_id = board_url.split('boards/').last.split('/').first

          chapter = new_chapter(board_id)
          expected_chapters << chapter
          block.call(chapter)
        end

        # keep track of when `chapter_list <<` is called, to check it gets all relevant chapters in the right order
        allow(stubbed_chapter_list).to receive(:<<) do |chapter|
          given_chapters << chapter
        end

        # keep track of when the function yields, to check it yields all relevant chapters in the right order
        handler.toc_to_chapterlist(params.merge(fic_toc_url: BOARDS_URL)) do |chapter|
          yielded_chapters << chapter
        end

        # and now compare expected values
        expect(given_params).to eq(expected_params)
        expect(given_chapters).to eq(expected_chapters)
        expect(yielded_chapters).to eq(expected_chapters)
      end

      # short
      it "works for single page" do
        stub_local('short', BOARDS_URL + '/')

        expected_params = [
          { board_url: 'https://glowfic.com/boards/5/' },
          { board_url: 'https://glowfic.com/boards/7/' },
          { board_url: 'https://glowfic.com/boards/6/' },
          { board_url: 'https://glowfic.com/boards/4/' }
        ]

        test_yields(handler, expected_params, 4)
      end

      # long_{1,2}
      it "works for many pages" do
        stub_local('long_1', BOARDS_URL + '/')
        stub_local('long_2', BOARDS_URL + '/?page=2')

        expected_params = 5.upto(30).collect do |i|
          { board_url: "https://glowfic.com/boards/#{i}/" }
        end

        test_yields(handler, expected_params, 26)
      end

      # short
      it "ignores boards in CONST_BOARDS constant" do
        stub_local('short', BOARDS_URL + '/')

        expected_params = [
          { board_url: 'https://glowfic.com/boards/5/' },
          { board_url: 'https://glowfic.com/boards/7/' },
          { board_url: 'https://glowfic.com/boards/6/' },
          { board_url: 'https://glowfic.com/boards/4/' }
        ]

        stub_const('GlowficIndexHandlers::CONST_BOARDS', [])
        test_yields(handler, expected_params, 4)

        stub_const('GlowficIndexHandlers::CONST_BOARDS', ['Sandboxes'])
        test_yields(handler, expected_params[1..-1], 3)

        stub_const('GlowficIndexHandlers::CONST_BOARDS', ['Board3'])
        test_yields(handler, expected_params[0..-2], 3)

        stub_const('GlowficIndexHandlers::CONST_BOARDS', ['Sandboxes', 'Board1', 'Board2', 'Board3'])
        test_yields(handler, [], 0)
      end

      # short
      it "ignores boards in ignore_sections param" do
        stub_local('short', BOARDS_URL + '/')

        expected_params = [
          { board_url: 'https://glowfic.com/boards/5/' },
          { board_url: 'https://glowfic.com/boards/7/' },
          { board_url: 'https://glowfic.com/boards/6/' },
          { board_url: 'https://glowfic.com/boards/4/' }
        ]

        stub_const('GlowficIndexHandlers::CONST_BOARDS', [])

        test_yields(handler, expected_params, 4, ignore_sections: [])
        test_yields(handler, expected_params[1..-1], 3, ignore_sections: ['Sandboxes'])
        test_yields(handler, expected_params[0..-2], 3, ignore_sections: ['Board3'])
        test_yields(handler, [], 0, ignore_sections: ['Sandboxes', 'Board1', 'Board2', 'Board3'])
      end

      it "handles constellation archive"
      it "ignores archived constellation"
    end

    context "for single board" do
      before(:each) do
        allow(STDOUT).to receive(:puts)
        allow(LOG).to receive(:info)
        stub_chapter_list
      end

      it "calls board_to_block" do
        url = 'https://glowfic.com/boards/1/'

        expected_chapters = []
        given_chapters = [] # handed to chapter list by <<
        yielded_chapters = [] # handed to block to toc_to_chapterlist

        expect(handler).to receive(:board_to_block).with({board_url: url, reverse: false}) do |params, &block|
          board_url = params[:board_url]
          board_id = board_url.split('boards/').last.split('/').first

          chapter = new_chapter(board_id)
          expected_chapters << chapter
          block.call(chapter)
        end

        # keep track of when `chapter_list <<` is called, to check it gets all relevant chapters in the right order
        allow(stubbed_chapter_list).to receive(:<<) do |chapter|
          given_chapters << chapter
        end

        # keep track of when the function yields, to check it yields all relevant chapters in the right order
        handler.toc_to_chapterlist(fic_toc_url: url) do |chapter|
          yielded_chapters << chapter
        end

        # and now compare expected values
        expect(given_chapters).to eq(expected_chapters)
        expect(yielded_chapters).to eq(expected_chapters)
      end
    end

    context "for user page" do
      it "has more tests"
    end

    skip "has more tests"
  end

  skip "has more tests"
end
