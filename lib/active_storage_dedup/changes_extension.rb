# frozen_string_literal: true

module ActiveStorageDedup
  module ChangesExtension
    extend ActiveSupport::Concern

    # Patch Changes::CreateOne#find_or_build_blob to pass context
    def find_or_build_blob
      Rails.logger.debug "[ActiveStorageDedup] ChangesExtension#find_or_build_blob called for #{name} attachment"
      Rails.logger.debug "[ActiveStorageDedup] Attachable type: #{attachable.class.name}"

      case attachable
      when ActiveStorage::Blob
        attachable
      when ActionDispatch::Http::UploadedFile
        ActiveStorage::Blob.build_after_unfurling(
          io: attachable.open,
          filename: attachable.original_filename,
          content_type: attachable.content_type,
          __dedup_record: record,
          __dedup_attachment_name: name,
          service_name: attachment_service_name
        )
      when Rack::Test::UploadedFile
        ActiveStorage::Blob.build_after_unfurling(
          io: attachable.respond_to?(:open) ? attachable.open : attachable,
          filename: attachable.original_filename,
          content_type: attachable.content_type,
          __dedup_record: record,
          __dedup_attachment_name: name,
          service_name: attachment_service_name
        )
      when Hash
        ActiveStorage::Blob.build_after_unfurling(
          **attachable.reverse_merge(
            record: record,
            service_name: attachment_service_name
          ).symbolize_keys.merge(
            __dedup_record: record,
            __dedup_attachment_name: name
          )
        )
      when String
        ActiveStorage::Blob.find_signed!(attachable, record: record)
      when File
        ActiveStorage::Blob.build_after_unfurling(
          io: attachable,
          filename: File.basename(attachable),
          __dedup_record: record,
          __dedup_attachment_name: name,
          service_name: attachment_service_name
        )
      when Pathname
        ActiveStorage::Blob.build_after_unfurling(
          io: attachable.open,
          filename: File.basename(attachable),
          __dedup_record: record,
          __dedup_attachment_name: name,
          service_name: attachment_service_name
        )
      else
        raise(
          ArgumentError,
          "Could not find or build blob: expected attachable, " \
            "got #{attachable.inspect}"
        )
      end
    end
  end
end
