# frozen_string_literal: true

require "logger"

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

    # Logger used by the gem (default: Rails.logger when Rails is loaded, else Logger.new($stdout))
    # Set to any Logger-compatible object to redirect gem output, or to Logger.new(IO::NULL) to silence
    attr_writer :logger

    def initialize
      @enabled = true
      @deduplicate_by_default = true
      @auto_purge_orphans = true
      Rails.logger.debug "[ActiveStorageDedup] Configuration initialized with defaults: enabled=#{@enabled}, deduplicate_by_default=#{@deduplicate_by_default}, auto_purge_orphans=#{@auto_purge_orphans}" if defined?(Rails) && Rails.logger
    end

    def logger
      @logger ||= default_logger
    end

    private

    def default_logger
      if defined?(Rails) && Rails.logger
        Rails.logger
      else
        Logger.new($stdout)
      end
    end
  end

  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def logger
      configuration.logger
    end

    def configure
      logger.debug "[ActiveStorageDedup] Configuring ActiveStorageDedup..."
      yield(configuration)
      logger.info "[ActiveStorageDedup] Configuration updated: enabled=#{configuration.enabled}, deduplicate_by_default=#{configuration.deduplicate_by_default}, auto_purge_orphans=#{configuration.auto_purge_orphans}"
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
      logger.debug "[ActiveStorageDedup] Registered attachment #{key} with deduplicate=#{deduplicate}"
    end

    def deduplicate_enabled_for?(record, attachment_name)
      # First check: Is the gem enabled at all?
      unless configuration.enabled
        logger.debug "[ActiveStorageDedup] Gem is disabled globally (enabled=false)"
        return false
      end

      key = "#{record.class.name}##{attachment_name}"
      settings = attachment_settings[key]

      # Second check: Model-level setting takes precedence over global default
      # If model explicitly sets deduplicate: true/false, use that
      # Otherwise, fall back to configuration.deduplicate_by_default
      if settings.nil?
        result = configuration.deduplicate_by_default
        logger.debug "[ActiveStorageDedup] Deduplication check for #{key}: #{result} (using deduplicate_by_default)"
      else
        result = settings[:deduplicate]
        logger.debug "[ActiveStorageDedup] Deduplication check for #{key}: #{result} (model-level override)"
      end

      result
    end
  end
end
