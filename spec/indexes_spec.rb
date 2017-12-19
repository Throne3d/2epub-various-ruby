require 'handlers_indexes'

RSpec.describe GlowficIndexHandlers do
  describe 'get_handler_for' do
    it 'returns handler if match is found' do
      expect(GlowficIndexHandlers.get_handler_for(:constellation)).to eq(GlowficIndexHandlers::ConstellationIndexHandler)
    end

    it 'returns empty if no match' do
      expect(GlowficIndexHandlers.get_handler_for(:nonexistent)).to be_blank
    end
  end
end
