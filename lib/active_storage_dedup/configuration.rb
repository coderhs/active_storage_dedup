# frozen_string_literal: true

module ActiveStorageDedup
  class Configuration
    # Master switch to enable/disable the entire gem (default: true)
    # If false, no deduplication or lifecycle management will occur at all
    attr_accessor :enabled

    # Default deduplication setting for attachments when gem is enabled (default: true)
    # This can be overridden per-attachment using the deduplicate: option
    # Only applies when enabled = true
    attr_accessor :deduplicate_by_default

    # Automatically purge orphaned blobs when reference_count reaches 0 (default: true)
    # Only applies when enabled = true
    attr_accessor :auto_purge_orphans

    def initialize
      @enabled = true
      @deduplicate_by_default = true
      @auto_purge_orphans = true
      Rails.logger.debug "[ActiveStorageDedup] Configuration initialized with defaults: enabled=#{@enabled}, deduplicate_by_default=#{@deduplicate_by_default}, auto_purge_orphans=#{@auto_purge_orphans}" if defined?(Rails)
    end
  end

  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      Rails.logger.debug "[ActiveStorageDedup] Configuring ActiveStorageDedup..." if defined?(Rails)
      yield(configuration)
      Rails.logger.info "[ActiveStorageDedup] Configuration updated: enabled=#{configuration.enabled}, deduplicate_by_default=#{configuration.deduplicate_by_default}, auto_purge_orphans=#{configuration.auto_purge_orphans}" if defined?(Rails)
    end

    def enabled?
      configuration.enabled
    end

    # Track which attachments have deduplicate disabled
    def attachment_settings
      @attachment_settings ||= {}
    end

    def register_attachment(model_name, attachment_name, deduplicate:)
      key = "#{model_name}##{attachment_name}"
      attachment_settings[key] = { deduplicate: deduplicate }
      Rails.logger.debug "[ActiveStorageDedup] Registered attachment #{key} with deduplicate=#{deduplicate}" if defined?(Rails)
    end

    def deduplicate_enabled_for?(record, attachment_name)
      # First check: Is the gem enabled at all?
      unless configuration.enabled
        Rails.logger.debug "[ActiveStorageDedup] Gem is disabled globally (enabled=false)" if defined?(Rails)
        return false
      end

      key = "#{record.class.name}##{attachment_name}"
      settings = attachment_settings[key]

      # Second check: Model-level setting takes precedence over global default
      # If model explicitly sets deduplicate: true/false, use that
      # Otherwise, fall back to configuration.deduplicate_by_default
      if settings.nil?
        result = configuration.deduplicate_by_default
        Rails.logger.debug "[ActiveStorageDedup] Deduplication check for #{key}: #{result} (using deduplicate_by_default)" if defined?(Rails)
      else
        result = settings[:deduplicate]
        Rails.logger.debug "[ActiveStorageDedup] Deduplication check for #{key}: #{result} (model-level override)" if defined?(Rails)
      end

      result
    end
  end
end
