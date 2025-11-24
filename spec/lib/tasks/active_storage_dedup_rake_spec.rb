# frozen_string_literal: true

require "rake"

RSpec.describe "active_storage_dedup rake tasks" do
  before(:all) do
    Rake.application.rake_require "tasks/active_storage_dedup"
    Rake::Task.define_task(:environment)
  end

  before(:each) do
    Rake::Task["active_storage_dedup:report_duplicates"].reenable
    Rake::Task["active_storage_dedup:cleanup_all"].reenable
    Rake::Task["active_storage_dedup:backfill_reference_count"].reenable
  end

  let(:checksum) { Digest::MD5.base64digest("test content") }
  let(:service_name) { "test" }

  describe "active_storage_dedup:report_duplicates" do
    it "reports when no duplicates exist" do
      ActiveStorage::Blob.create!(
        key: "test-key",
        filename: "test.txt",
        byte_size: 100,
        checksum: checksum,
        service_name: service_name
      )

      expect do
        Rake::Task["active_storage_dedup:report_duplicates"].invoke
      end.to output(/No duplicate blobs found!/).to_stdout
    end

    it "reports duplicate blobs with details" do
      keeper = ActiveStorage::Blob.create!(
        key: "keeper-key",
        filename: "test.txt",
        byte_size: 1024,
        checksum: checksum,
        service_name: service_name,
        created_at: 1.hour.ago
      )

      duplicate = ActiveStorage::Blob.create!(
        key: "dup-key",
        filename: "test.txt",
        byte_size: 1024,
        checksum: checksum,
        service_name: service_name,
        created_at: 30.minutes.ago
      )

      duplicate_groups_stub = [
        double(checksum: checksum, service_name: service_name, blob_count: 2)
      ]
      allow(ActiveStorage::Blob).to receive_message_chain(:select, :group, :having, :order)
        .and_return(duplicate_groups_stub)
      allow(duplicate_groups_stub).to receive(:empty?).and_return(false)
      allow(duplicate_groups_stub).to receive(:count).and_return(1)

      output = capture_stdout do
        Rake::Task["active_storage_dedup:report_duplicates"].invoke
      end

      expect(output).to include("Scanning for duplicate blobs")
      expect(output).to include("Checksum: #{checksum}")
      expect(output).to include("Service: #{service_name}")
      expect(output).to include("Filename: test.txt")
      expect(output).to include("Total blobs: 2")
      expect(output).to include("Keeper blob ID: #{keeper.id}")
      expect(output).to include("Duplicate blob IDs: #{duplicate.id}")
      expect(output).to include("Total duplicate groups: 1")
      expect(output).to include("Total duplicate blobs: 1")
      expect(output).to include("Wasted storage")
    end

    it "formats bytes correctly" do
      ActiveStorage::Blob.create!(
        key: "keeper-key",
        filename: "large.txt",
        byte_size: 5_242_880,
        checksum: checksum,
        service_name: service_name,
        created_at: 1.hour.ago
      )

      ActiveStorage::Blob.create!(
        key: "dup-key",
        filename: "large.txt",
        byte_size: 5_242_880,
        checksum: checksum,
        service_name: service_name,
        created_at: 30.minutes.ago
      )

      duplicate_groups_stub = [
        double(checksum: checksum, service_name: service_name, blob_count: 2)
      ]
      allow(ActiveStorage::Blob).to receive_message_chain(:select, :group, :having, :order)
        .and_return(duplicate_groups_stub)
      allow(duplicate_groups_stub).to receive(:empty?).and_return(false)
      allow(duplicate_groups_stub).to receive(:count).and_return(1)

      output = capture_stdout do
        Rake::Task["active_storage_dedup:report_duplicates"].invoke
      end

      expect(output).to match(/Wasted storage:.*MB/)
    end

    it "reports multiple duplicate groups ordered by count" do
      checksum1 = Digest::MD5.base64digest("content1")
      checksum2 = Digest::MD5.base64digest("content2")

      3.times do |i|
        ActiveStorage::Blob.create!(
          key: "group1-#{i}",
          filename: "file1.txt",
          byte_size: 100,
          checksum: checksum1,
          service_name: service_name,
          created_at: i.hours.ago
        )
      end

      2.times do |i|
        ActiveStorage::Blob.create!(
          key: "group2-#{i}",
          filename: "file2.txt",
          byte_size: 200,
          checksum: checksum2,
          service_name: service_name,
          created_at: i.hours.ago
        )
      end

      duplicate_groups_stub = [
        double(checksum: checksum1, service_name: service_name, blob_count: 3),
        double(checksum: checksum2, service_name: service_name, blob_count: 2)
      ]
      allow(ActiveStorage::Blob).to receive_message_chain(:select, :group, :having, :order)
        .and_return(duplicate_groups_stub)
      allow(duplicate_groups_stub).to receive(:empty?).and_return(false)
      allow(duplicate_groups_stub).to receive(:count).and_return(2)

      output = capture_stdout do
        Rake::Task["active_storage_dedup:report_duplicates"].invoke
      end

      expect(output).to include("Total duplicate groups: 2")
      expect(output).to include("Total duplicate blobs: 3")
    end
  end

  describe "active_storage_dedup:cleanup_all" do
    it "runs the deduplication job" do
      expect(ActiveStorageDedup::DeduplicationJob).to receive(:perform_now)

      expect do
        Rake::Task["active_storage_dedup:cleanup_all"].invoke
      end.to output(/Running sanity check.*Cleanup complete/m).to_stdout
    end

    it "merges duplicate blobs" do
      ActiveStorage::Blob.create!(
        key: "keeper-key",
        filename: "test.txt",
        byte_size: 100,
        checksum: checksum,
        service_name: service_name,
        created_at: 1.hour.ago
      )

      ActiveStorage::Blob.create!(
        key: "dup-key",
        filename: "test.txt",
        byte_size: 100,
        checksum: checksum,
        service_name: service_name,
        created_at: 30.minutes.ago
      )

      allow(ActiveStorage::Blob).to receive_message_chain(:select, :group, :having, :count)
        .and_return({ [checksum, service_name] => 2 })

      initial_count = ActiveStorage::Blob.count
      expect(initial_count).to eq(2)

      Rake::Task["active_storage_dedup:cleanup_all"].invoke
    end
  end

  describe "active_storage_dedup:backfill_reference_count" do
    it "reports when all counts are correct" do
      blob = ActiveStorage::Blob.create!(
        key: "test-key",
        filename: "test.txt",
        byte_size: 100,
        checksum: checksum,
        service_name: service_name
      )
      blob.update_column(:reference_count, 0)

      output = capture_stdout do
        Rake::Task["active_storage_dedup:backfill_reference_count"].invoke
      end

      expect(output).to include("Backfilling reference_count")
      expect(output).to include("Backfill complete!")
      expect(output).to include("Total blobs: 1")
      expect(output).to include("Updated: 0")
    end

    it "updates incorrect reference counts" do
      user = User.create!(name: "Test User")

      blob = ActiveStorage::Blob.create_after_unfurling!(
        io: StringIO.new("test content"),
        filename: "test.txt"
      )

      user.avatar.attach(blob)

      blob.update_column(:reference_count, 5)

      output = capture_stdout do
        Rake::Task["active_storage_dedup:backfill_reference_count"].invoke
      end

      expect(output).to include("Updated: 1")

      expect(blob.reload.reference_count).to eq(1)
    end

    it "updates blobs with zero reference count" do
      blob = ActiveStorage::Blob.create_after_unfurling!(
        io: StringIO.new("test content"),
        filename: "test.txt"
      )

      blob.update_column(:reference_count, 10)

      output = capture_stdout do
        Rake::Task["active_storage_dedup:backfill_reference_count"].invoke
      end

      expect(output).to include("Updated: 1")
      expect(blob.reload.reference_count).to eq(0)
    end

    it "processes large batches with progress output" do
      150.times do |i|
        blob = ActiveStorage::Blob.create!(
          key: "blob-#{i}",
          filename: "file-#{i}.txt",
          byte_size: 100,
          checksum: Digest::MD5.base64digest("content-#{i}"),
          service_name: service_name
        )
        blob.update_column(:reference_count, 10) if i.even?
      end

      output = capture_stdout do
        Rake::Task["active_storage_dedup:backfill_reference_count"].invoke
      end

      expect(output).to include("Processed 100/150 blobs")
      expect(output).to include("Total blobs: 150")
      expect(output).to include("Updated: 75")
    end

    it "handles blobs with multiple attachments" do
      user1 = User.create!(name: "User 1")
      user2 = User.create!(name: "User 2")

      blob = ActiveStorage::Blob.create_after_unfurling!(
        io: StringIO.new("test content"),
        filename: "test.txt"
      )

      user1.avatar.attach(blob)
      user2.avatar.attach(blob)

      blob.update_column(:reference_count, 0)

      Rake::Task["active_storage_dedup:backfill_reference_count"].invoke

      expect(blob.reload.reference_count).to eq(2)
    end
  end

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
