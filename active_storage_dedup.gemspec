# frozen_string_literal: true

require_relative "lib/active_storage_dedup/version"

Gem::Specification.new do |spec|
  spec.name = "active_storage_dedup"
  spec.version = ActiveStorageDedup::VERSION
  spec.authors = ["coderhs"]
  spec.email = ["mailme@hsps.in"]

  spec.summary = "Deduplication for Active Storage uploads"
  spec.description = "Prevents duplicate file uploads in Active Storage by reusing existing blobs with matching checksums and service names"
  spec.homepage = "https://github.com/coderhs/active_storage_dedup"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/coderhs/active_storage_dedup"
  spec.metadata["changelog_uri"] = "https://github.com/coderhs/active_storage_dedup/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "activestorage", ">= 6.0.0"
  spec.add_dependency "rails", ">= 6.0.0"

  # Development dependencies
  spec.add_development_dependency "combustion", "~> 1.3"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rspec-rails"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "sqlite3"
end
