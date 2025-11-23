# frozen_string_literal: true

module ActiveStorageDedup
  module AttachmentOptions
    def has_one_attached(name, dependent: :purge_later, service: nil,
                         strict_loading: false, deduplicate: true, **options)
      ActiveStorageDedup.register_attachment(self.name, name, deduplicate: deduplicate)

      super(name, dependent: dependent, service: service,
            strict_loading: strict_loading, **options)
    end

    def has_many_attached(name, dependent: :purge_later, service: nil,
                          strict_loading: false, deduplicate: true, **options)
      ActiveStorageDedup.register_attachment(self.name, name, deduplicate: deduplicate)

      super(name, dependent: dependent, service: service,
            strict_loading: strict_loading, **options)
    end
  end
end
