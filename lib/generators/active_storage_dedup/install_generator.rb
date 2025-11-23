# frozen_string_literal: true

require "rails/generators"
require "rails/generators/migration"

module ActiveStorageDedup
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Creates ActiveStorageDedup initializer and migration files"

      def self.next_migration_number(path)
        next_migration_number = current_migration_number(path) + 1
        ActiveRecord::Migration.next_migration_number(next_migration_number)
      end

      def copy_initializer
        template "initializer.rb", "config/initializers/active_storage_dedup.rb"
      end

      def copy_migrations
        migration_template(
          "add_active_storage_dedup.rb.erb",
          "db/migrate/add_active_storage_dedup.rb"
        )
      end

      def show_readme
        readme "README" if behavior == :invoke
      end
    end
  end
end
