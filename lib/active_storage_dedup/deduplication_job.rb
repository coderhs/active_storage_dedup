# frozen_string_literal: true

module ActiveStorageDedup
  class DeduplicationJob < ActiveJob::Base
    queue_as :default

    # Sanity check job to find and merge duplicate blobs across the entire database
    # Can be run on-demand or scheduled (daily/weekly) to clean up any duplicates
    # that may have slipped through due to race conditions
    #
    # @example Run manually
    #   ActiveStorageDedup::DeduplicationJob.perform_now
    #
    # @example Schedule with whenever gem
    #   every 1.day, at: '2:00 am' do
    #     runner "ActiveStorageDedup::DeduplicationJob.perform_later"
    #   end
    #
    # @example Schedule with sidekiq-cron
    #   ActiveStorageDedup::DeduplicationJob.set(cron: '0 2 * * *').perform_later
    def perform
      ActiveStorageDedup.logger.info "[ActiveStorageDedup] 🔍 Starting sanity check - scanning for duplicate blobs..."

      # Find all checksum+service combinations that have duplicates
      duplicate_groups = ActiveStorage::Blob
                         .select(:checksum, :service_name)
                         .group(:checksum, :service_name)
                         .having("COUNT(*) > 1")
                         .count

      if duplicate_groups.empty?
        ActiveStorageDedup.logger.info "[ActiveStorageDedup] ✓ No duplicate blobs found - database is clean!"
        return
      end

      ActiveStorageDedup.logger.info "[ActiveStorageDedup] Found #{duplicate_groups.size} group(s) with duplicates"

      total_merged = 0
      duplicate_groups.each_key do |(checksum, service_name)|
        merged = process_duplicate_group(checksum, service_name)
        total_merged += merged
      end

      ActiveStorageDedup.logger.info "[ActiveStorageDedup] ✓ Sanity check complete - merged #{total_merged} duplicate blob(s)"
    end

    private

    def process_duplicate_group(checksum, service_name)
      ActiveStorageDedup.logger.debug "[ActiveStorageDedup] Processing duplicate group: checksum=#{checksum[0..12]}..., service=#{service_name}"

      # Find all blobs with same checksum and service
      duplicate_blobs = ActiveStorage::Blob
                        .where(checksum: checksum, service_name: service_name)
                        .order(:created_at)
                        .to_a

      ActiveStorageDedup.logger.debug "[ActiveStorageDedup] Found #{duplicate_blobs.size} blob(s) with checksum #{checksum[0..12]}..."

      # Keep the oldest blob (first created)
      keeper = duplicate_blobs.first
      duplicates = duplicate_blobs[1..]

      ActiveStorageDedup.logger.info "[ActiveStorageDedup] 🔄 Merging #{duplicates.size} duplicate(s) into blob #{keeper.id} (checksum: #{checksum[0..12]}...)"

      # Merge each duplicate into the keeper
      duplicates.each do |duplicate_blob|
        merge_duplicate(keeper, duplicate_blob)
      end

      duplicates.size
    end

    def merge_duplicate(keeper, duplicate)
      ActiveStorageDedup.logger.debug "[ActiveStorageDedup] Merging blob #{duplicate.id} into keeper #{keeper.id}..."

      # Count attachments to move
      attachment_count = duplicate.attachments.count
      ActiveStorageDedup.logger.debug "[ActiveStorageDedup] Moving #{attachment_count} attachment(s) from blob #{duplicate.id} to #{keeper.id}"

      # Move all attachments from duplicate to keeper
      duplicate.attachments.update_all(blob_id: keeper.id)

      # Update counter cache on keeper
      # Rails counter cache won't auto-update since we used update_all
      keeper.increment!(:reference_count, attachment_count)
      ActiveStorageDedup.logger.debug "[ActiveStorageDedup] Updated keeper #{keeper.id} reference_count to #{keeper.reference_count}"

      # Delete duplicate blob record (without purging file, since it's same as keeper)
      duplicate.delete
      ActiveStorageDedup.logger.debug "[ActiveStorageDedup] Deleted duplicate blob #{duplicate.id} record"

      ActiveStorageDedup.logger.info "[ActiveStorageDedup] ✓ Merged blob #{duplicate.id} (#{attachment_count} attachment(s)) into #{keeper.id}"
    rescue StandardError => e
      ActiveStorageDedup.logger.error "[ActiveStorageDedup] ✗ Error merging blob #{duplicate.id}: #{e.class.name} - #{e.message}"
      ActiveStorageDedup.logger.debug "[ActiveStorageDedup] Error backtrace: #{e.backtrace.first(5).join("\n")}"
      # Don't raise - allow job to complete for other duplicates
    end
  end
end
