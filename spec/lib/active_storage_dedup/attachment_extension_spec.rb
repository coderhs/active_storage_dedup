# frozen_string_literal: true

require "stringio"

RSpec.describe ActiveStorageDedup::AttachmentExtension do
  let(:user) { User.create!(name: "Test User") }
  let(:test_file) { StringIO.new("test content") }

  before do
    ActiveStorageDedup.configuration.enabled = true
    ActiveStorageDedup.configuration.deduplicate_by_default = true
    ActiveStorageDedup.configuration.auto_purge_orphans = true
  end

  describe "counter cache" do
    it "increments reference_count when attachment is created" do
      blob = ActiveStorage::Blob.create_after_unfurling!(
        io: test_file,
        filename: "test.txt"
      )

      expect {
        user.avatar.attach(blob)
      }.to change { blob.reload.reference_count }.from(0).to(1)
    end

    it "decrements reference_count when attachment is destroyed" do
      user.avatar.attach(io: test_file, filename: "test.txt")
      blob = user.avatar.blob

      expect {
        user.avatar.purge
      }.to change { blob.reload.reference_count rescue 0 }.from(1).to(0)
    end

    it "tracks multiple attachments correctly" do
      blob = ActiveStorage::Blob.create_after_unfurling!(
        io: StringIO.new("test content"),
        filename: "test.txt"
      )

      user1 = User.create!(name: "User 1")
      user2 = User.create!(name: "User 2")

      user1.avatar.attach(blob)
      expect(blob.reload.reference_count).to eq(1)

      user2.avatar.attach(blob)
      expect(blob.reload.reference_count).to eq(2)

      # Use destroy on the attachment record instead of purge to trigger counter_cache
      user1.avatar.attachment.destroy
      expect(blob.reload.reference_count).to eq(1)
    end
  end

  describe "auto purge orphans" do
    it "purges blob when last attachment is destroyed" do
      user.avatar.attach(io: StringIO.new("test content"), filename: "test.txt")
      blob = user.avatar.blob

      expect {
        user.avatar.purge
      }.to change { ActiveStorage::Blob.exists?(blob.id) }.from(true).to(false)
    end

    it "does not purge blob when other attachments exist" do
      blob = ActiveStorage::Blob.create_after_unfurling!(
        io: StringIO.new("test content"),
        filename: "test.txt"
      )

      user1 = User.create!(name: "User 1")
      user2 = User.create!(name: "User 2")

      user1.avatar.attach(blob)
      user2.avatar.attach(blob)

      expect {
        user1.avatar.attachment.destroy
      }.not_to change { ActiveStorage::Blob.exists?(blob.id) }

      expect(blob.reload.reference_count).to eq(1)
    end

    context "when disabled" do
      before do
        ActiveStorageDedup.configuration.auto_purge_orphans = false
      end

      it "does not purge orphaned blobs" do
        user.avatar.attach(io: StringIO.new("test content"), filename: "test.txt")
        blob = user.avatar.blob

        expect {
          user.avatar.attachment.destroy
        }.not_to change { ActiveStorage::Blob.exists?(blob.id) }

        expect(blob.reload.reference_count).to eq(0)
      end
    end
  end
end
