# frozen_string_literal: true

namespace :active_storage_dedup do
  desc "Report duplicate blobs grouped by checksum and service"
  task report_duplicates: :environment do
    puts "Scanning for duplicate blobs...\n\n"

    # Group blobs by checksum and service_name, find groups with duplicates
    duplicate_groups = ActiveStorage::Blob
      .select("checksum, service_name, COUNT(*) as blob_count")
      .group(:checksum, :service_name)
      .having("COUNT(*) > 1")
      .order("blob_count DESC")

    if duplicate_groups.empty?
      puts "No duplicate blobs found!"
      next
    end

    total_duplicates = 0
    total_wasted_storage = 0

    duplicate_groups.each do |group|
      blobs = ActiveStorage::Blob
        .where(checksum: group.checksum, service_name: group.service_name)
        .order(:created_at)

      keeper = blobs.first
      duplicates = blobs[1..]

      # Calculate wasted storage (size of duplicate blobs)
      wasted_bytes = duplicates.sum(&:byte_size)
      total_wasted_storage += wasted_bytes

      puts "Checksum: #{group.checksum}"
      puts "Service: #{group.service_name}"
      puts "Filename: #{keeper.filename}"
      puts "Total blobs: #{blobs.count}"
      puts "Keeper blob ID: #{keeper.id} (#{keeper.attachments.count} attachments)"
      puts "Duplicate blob IDs: #{duplicates.map(&:id).join(', ')}"
      puts "Total attachments across duplicates: #{duplicates.sum { |b| b.attachments.count }}"
      puts "Wasted storage: #{format_bytes(wasted_bytes)}"
      puts "-" * 80
      puts

      total_duplicates += duplicates.count
    end

    puts "\nSummary:"
    puts "Total duplicate groups: #{duplicate_groups.count}"
    puts "Total duplicate blobs: #{total_duplicates}"
    puts "Total wasted storage: #{format_bytes(total_wasted_storage)}"
  end

  desc "Clean up all duplicate blobs by merging them (sanity check)"
  task cleanup_all: :environment do
    puts "Running sanity check to find and merge duplicate blobs...\n\n"

    # Run the deduplication job
    ActiveStorageDedup::DeduplicationJob.perform_now

    puts "\nCleanup complete! Check logs for details."
  end

  desc "Backfill reference_count for existing blobs"
  task backfill_reference_count: :environment do
    puts "Backfilling reference_count for all blobs...\n\n"

    total_blobs = ActiveStorage::Blob.count
    updated = 0

    ActiveStorage::Blob.find_each.with_index do |blob, index|
      actual_count = blob.attachments.count
      current_count = blob.reference_count || 0

      if actual_count != current_count
        blob.update_column(:reference_count, actual_count)
        updated += 1
      end

      if (index + 1) % 100 == 0
        puts "Processed #{index + 1}/#{total_blobs} blobs..."
      end
    end

    puts "\nBackfill complete!"
    puts "Total blobs: #{total_blobs}"
    puts "Updated: #{updated}"
  end

  # Helper method to format bytes into human-readable format
  def format_bytes(bytes)
    return "0 B" if bytes.zero?

    units = ["B", "KB", "MB", "GB", "TB"]
    exp = (Math.log(bytes) / Math.log(1024)).floor
    exp = [exp, units.length - 1].min

    format("%.2f %s", bytes.to_f / (1024**exp), units[exp])
  end
end
