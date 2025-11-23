# ActiveStorageDedup

Automatic deduplication for Rails Active Storage. Prevents duplicate file uploads by reusing existing blobs with matching checksums, saving storage space and bandwidth.

## Features

- **Automatic Deduplication**: Reuses existing blobs when identical files are uploaded
- **All Upload Methods Supported**: Works with form uploads, direct uploads, and programmatic attachments
- **Service-Aware**: Properly handles multiple storage services (local, S3, etc.)
- **Reference Counting**: Tracks blob usage with automatic counter cache
- **Three-Level Configuration**: Master switch, global default, and per-attachment control
- **Sanity Check Job**: Periodic job to clean up any duplicates that slip through
- **Auto-Purge Orphans**: Automatically removes blobs when no attachments reference them
- **Zero Dependencies**: Works with standard Rails Active Storage

## Demo/Implementation APP

[Github Repo](https://github.com/coderhs/rails-storage-example)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'active_storage_dedup'
```

Then execute:

```bash
bundle install
```

Run the install generator to create the migration:

```bash
rails generate active_storage_dedup:install
```

This will:
- Create the migration to add `reference_count` column to `active_storage_blobs`
- Create composite index on `[checksum, service_name]` for fast duplicate lookups
- Create an initializer at `config/initializers/active_storage_dedup.rb` with default configuration

Finally, run the migration:

```bash
rails db:migrate
```

## Usage

### Basic Setup

ActiveStorageDedup works automatically with all Active Storage attachments. No code changes required!

```ruby
class User < ApplicationRecord
  has_one_attached :avatar
  has_many_attached :documents
end

# Upload a file
user.avatar.attach(io: File.open('photo.jpg'), filename: 'photo.jpg')

# Upload the same file to another user - reuses existing blob!
another_user.avatar.attach(io: File.open('photo.jpg'), filename: 'photo.jpg')
```

### Configuration

The install generator creates `config/initializers/active_storage_dedup.rb` with these options:

```ruby
ActiveStorageDedup.configure do |config|
  # Master switch to enable/disable the entire gem (default: true)
  # Set to false to completely disable all deduplication and lifecycle management
  config.enabled = true

  # Default deduplication setting for all attachments (default: true)
  # Controls whether attachments deduplicate by default when gem is enabled
  # Can be overridden per-attachment
  config.deduplicate_by_default = true

  # Auto-purge blobs when reference_count reaches 0 (default: true)
  config.auto_purge_orphans = true
end
```

### Three-Level Control

#### Level 1: Master Switch (`enabled`)
Completely enable or disable the gem:

```ruby
config.enabled = false  # Gem does nothing - Active Storage works normally
```

#### Level 2: Global Default (`deduplicate_by_default`)
Set the default behavior for all attachments:

```ruby
# Opt-out pattern: deduplicate by default, disable selectively
config.enabled = true
config.deduplicate_by_default = true

class Product < ApplicationRecord
  has_many_attached :images              # ✅ Deduplicates
  has_one_attached :badge, deduplicate: false  # ❌ Doesn't deduplicate
end
```

```ruby
# Opt-in pattern: don't deduplicate by default, enable selectively
config.enabled = true
config.deduplicate_by_default = false

class Product < ApplicationRecord
  has_many_attached :images, deduplicate: true  # ✅ Deduplicates
  has_one_attached :avatar                      # ❌ Doesn't deduplicate
end
```

#### Level 3: Per-Attachment Override
Override the global default for specific attachments:

```ruby
class Product < ApplicationRecord
  # Uses config.deduplicate_by_default
  has_one_attached :image

  # Explicit override: always deduplicate
  has_many_attached :photos, deduplicate: true

  # Explicit override: never deduplicate
  has_one_attached :unique_badge, deduplicate: false
end
```

### Rake Tasks

#### Report Duplicates

See all duplicate blobs (dry run):

```bash
rails active_storage_dedup:report_duplicates
```

Output:
```
Checksum: abc123def456...
Service: local
Filename: photo.jpg
Total blobs: 3
Keeper blob ID: 42 (1 attachments)
Duplicate blob IDs: 43, 44
Total attachments across duplicates: 2
Wasted storage: 2.5 MB
```

#### Clean Up All Duplicates

Run the sanity check job to find and merge all duplicate blobs:

```bash
rails active_storage_dedup:cleanup_all
```

Or run the job directly:

```ruby
ActiveStorageDedup::DeduplicationJob.perform_now
```

#### Backfill Reference Counts

Recalculate reference counts for existing blobs:

```bash
rails active_storage_dedup:backfill_reference_count
```

### Scheduled Cleanup (Recommended)

Due to race conditions during concurrent uploads, duplicates may occasionally slip through. Run the sanity check job periodically to clean them up:

**With whenever gem:**

```ruby
# config/schedule.rb
every 1.week, at: '2:00 am' do
  runner "ActiveStorageDedup::DeduplicationJob.perform_later"
end
```

**With sidekiq-cron:**

```ruby
# config/initializers/sidekiq.rb
Sidekiq::Cron::Job.create(
  name: 'Active Storage Dedup - weekly cleanup',
  cron: '0 2 * * 0',  # 2 AM every Sunday
  class: 'ActiveStorageDedup::DeduplicationJob'
)
```

**With Rails built-in scheduler (Good Job, Solid Queue, etc.):**

```ruby
# config/recurring.yml
active_storage_dedup_cleanup:
  class: ActiveStorageDedup::DeduplicationJob
  schedule: "weekly on sunday at 2am"
```

**With cron:**

```bash
# Weekly cleanup every Sunday at 2 AM
0 2 * * 0 cd /app && bin/rails runner "ActiveStorageDedup::DeduplicationJob.perform_now"
```

## How It Works

### Deduplication Strategy

ActiveStorageDedup uses `[checksum, service_name]` as the deduplication key:

- **Checksum**: Active Storage's built-in MD5 checksum
- **Service Name**: Storage service (local, S3, etc.)

When a file is uploaded:

1. Checksum is calculated
2. Existing blob with same checksum + service is searched
3. If found, existing blob is reused
4. If not found, new blob is created

### Three Interception Points

The gem patches three Active Storage methods to cover all upload flows:

1. **`build_after_unfurling`**: Form uploads (Rails 6.1+)
2. **`create_before_direct_upload!`**: Direct uploads to cloud storage
3. **`create_after_unfurling!`**: Programmatic attachments via `attach()`

### Reference Counting

Uses Rails' built-in counter cache:

```ruby
# Automatically incremented when attachment created
belongs_to :blob, counter_cache: :reference_count

# Check references
blob.reference_count  # => 3
blob.attachments.count  # => 3
```

### Auto-Purge Orphans

When an attachment is destroyed:

1. Counter cache automatically decrements
2. If `reference_count` reaches 0, blob is purged
3. Physical file is deleted from storage

## Advanced Usage

### Direct Uploads

Works seamlessly with Active Storage's direct upload feature:

```javascript
// Client-side - no changes needed!
// ActiveStorageDedup automatically deduplicates on the server
```

### Multiple Services

Blobs are service-specific. Same file on different services = separate blobs:

```ruby
user.avatar.attach(
  io: File.open('photo.jpg'),
  filename: 'photo.jpg',
  service_name: :local  # Uses local storage
)

user.documents.attach(
  io: File.open('photo.jpg'),
  filename: 'photo.jpg',
  service_name: :amazon  # Creates separate blob on S3
)
```

### Manual Sanity Check

Run the sanity check job manually to clean up all duplicates:

```ruby
# Run synchronously (blocks until complete)
ActiveStorageDedup::DeduplicationJob.perform_now

# Run asynchronously (queues the job)
ActiveStorageDedup::DeduplicationJob.perform_later
```

The job will:
1. Scan the database for all duplicate blob groups (same checksum + service)
2. For each group, keep the oldest blob and merge duplicates into it
3. Move all attachments from duplicate blobs to the keeper
4. Update reference counts
5. Delete duplicate blob records

## Examples

### Reference Counting

```ruby
blob = ActiveStorage::Blob.create_after_upload!(
  io: File.open('shared.jpg'),
  filename: 'shared.jpg'
)

user1.avatar.attach(blob)
blob.reference_count  # => 1

user2.avatar.attach(blob)
blob.reference_count  # => 2

user1.avatar.purge
blob.reference_count  # => 1

user2.avatar.purge
# => Blob automatically purged (reference_count = 0)
```

### Environment-Specific Configuration

```ruby
# config/environments/development.rb
Rails.application.configure do
  # Disable in development for faster uploads during testing
  ActiveStorageDedup.configure do |config|
    config.enabled = false
  end
end

# config/environments/production.rb
Rails.application.configure do
  # Enable in production to save storage
  ActiveStorageDedup.configure do |config|
    config.enabled = true
    config.deduplicate_by_default = true
  end
end
```

## Quick Reference

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `enabled` | `true` | Master switch - disables entire gem when false |
| `deduplicate_by_default` | `true` | Default behavior for attachments (can be overridden) |
| `auto_purge_orphans` | `true` | Automatically delete blobs when reference_count = 0 |

### Model Options

```ruby
has_one_attached :avatar                    # Uses deduplicate_by_default
has_many_attached :docs, deduplicate: true  # Always deduplicate
has_one_attached :badge, deduplicate: false # Never deduplicate
```

### Rake Tasks

| Task | Description |
|------|-------------|
| `rails active_storage_dedup:report_duplicates` | Show all duplicate blobs (dry run) |
| `rails active_storage_dedup:cleanup_all` | Run sanity check to merge duplicates |
| `rails active_storage_dedup:backfill_reference_count` | Recalculate reference counts |

### Jobs

```ruby
# Run sanity check manually
ActiveStorageDedup::DeduplicationJob.perform_now

# Queue sanity check
ActiveStorageDedup::DeduplicationJob.perform_later
```

## Requirements

- Rails 6.0+
- Active Storage configured
- ActiveJob (for background cleanup)

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/coderhs/active_storage_dedup. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/coderhs/active_storage_dedup/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the ActiveStorageDedup project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/coderhs/active_storage_dedup/blob/main/CODE_OF_CONDUCT.md).
