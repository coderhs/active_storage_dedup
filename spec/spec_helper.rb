# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  add_filter "/vendor/"
end

ENV["RAILS_ENV"] = "test"

require "bundler/setup"
require "combustion"

# Initialize Combustion with Active Storage
Combustion.path = "spec/internal"
Combustion.initialize! :active_record, :active_storage, :active_job

load Rails.root.join("db", "schema.rb") if File.exist?(Rails.root.join("db", "schema.rb"))

require "active_storage_dedup"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.around(:each) do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end

  config.before(:each) do
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    ActiveJob::Base.queue_adapter.performed_jobs.clear
  end
end
