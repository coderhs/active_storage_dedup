# frozen_string_literal: true

RSpec.describe ActiveStorageDedup::Configuration do
  describe "default configuration" do
    it "enables deduplication by default" do
      config = described_class.new
      expect(config.enabled).to be true
    end

    it "deduplicates by default" do
      config = described_class.new
      expect(config.deduplicate_by_default).to be true
    end

    it "auto purges orphans by default" do
      config = described_class.new
      expect(config.auto_purge_orphans).to be true
    end
  end

  describe "#deduplicate_enabled_for?" do
    let(:user) { User.new }

    context "when globally enabled" do
      before do
        ActiveStorageDedup.configuration.enabled = true
      end

      it "returns true for attachments without specific settings" do
        expect(ActiveStorageDedup.deduplicate_enabled_for?(user, :avatar)).to be true
      end

      it "returns false for attachments with deduplicate: false" do
        product = Product.new
        expect(ActiveStorageDedup.deduplicate_enabled_for?(product, :photo)).to be false
      end
    end

    context "when globally disabled" do
      before do
        ActiveStorageDedup.configuration.enabled = false
      end

      it "returns false regardless of attachment settings" do
        expect(ActiveStorageDedup.deduplicate_enabled_for?(user, :avatar)).to be false
      end
    end
  end
end
