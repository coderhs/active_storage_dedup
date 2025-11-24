# frozen_string_literal: true

require "stringio"

RSpec.describe ActiveStorageDedup::BlobDeduplication do
  let(:test_file_content) { "test file content" }
  let(:test_io) { StringIO.new(test_file_content) }
  let(:filename) { "test.txt" }
  let(:service_name) { "local" }

  before do
    ActiveStorageDedup.configuration.enabled = true
    # Mock ActiveStorage::Service
    allow(ActiveStorage::Blob).to receive(:service).and_return(
      double(name: service_name)
    )
  end

  describe ".build_after_unfurling" do
    context "when deduplication is enabled" do
      let(:user) { User.create!(name: "Test User") }

      it "creates a new blob if no duplicate exists" do
        blob = ActiveStorage::Blob.build_after_unfurling(
          io: test_io,
          filename: filename,
          __dedup_record: user,
          __dedup_attachment_name: :avatar
        )
        expect(blob).to be_present
        expect(blob.filename.to_s).to eq(filename)

        expect {
          blob.save!
        }.to change { ActiveStorage::Blob.count }.by(1)
      end

      it "reuses existing blob with same checksum and service" do
        # Create initial blob
        first_blob = ActiveStorage::Blob.build_after_unfurling(
          io: StringIO.new(test_file_content),
          filename: filename,
          __dedup_record: user,
          __dedup_attachment_name: :avatar
        )
        first_blob.save!

        # Try to create another blob with same content
        test_io.rewind
        second_blob = ActiveStorage::Blob.build_after_unfurling(
          io: test_io,
          filename: filename,
          __dedup_record: user,
          __dedup_attachment_name: :avatar
        )

        expect(second_blob.id).to eq(first_blob.id)
        expect(ActiveStorage::Blob.count).to eq(1)
      end

      it "creates different blobs for different services" do
        # Create blob with first service
        first_blob = ActiveStorage::Blob.build_after_unfurling(
          io: StringIO.new(test_file_content),
          filename: filename,
          service_name: "local",
          __dedup_record: user,
          __dedup_attachment_name: :avatar
        )
        first_blob.save!

        # Create blob with different service
        test_io.rewind
        second_blob = ActiveStorage::Blob.build_after_unfurling(
          io: test_io,
          filename: filename,
          service_name: "s3",
          __dedup_record: user,
          __dedup_attachment_name: :avatar
        )
        second_blob.save!

        expect(second_blob.id).not_to eq(first_blob.id)
        expect(ActiveStorage::Blob.count).to eq(2)
      end
    end

    context "when deduplication is disabled for attachment" do
      let(:product) { Product.create!(name: "Test Product") }

      it "creates new blob even if duplicate exists" do
        # Create initial blob
        first_blob = ActiveStorage::Blob.build_after_unfurling(
          io: StringIO.new(test_file_content),
          filename: filename,
          __dedup_record: product,
          __dedup_attachment_name: :photo
        )
        first_blob.save!

        # Create another blob with same content
        test_io.rewind
        second_blob = ActiveStorage::Blob.build_after_unfurling(
          io: test_io,
          filename: filename,
          __dedup_record: product,
          __dedup_attachment_name: :photo
        )
        second_blob.save!

        expect(second_blob.id).not_to eq(first_blob.id)
        expect(ActiveStorage::Blob.count).to eq(2)
      end
    end

    context "when context is missing" do
      it "uses global setting when context is missing" do
        # When no context is provided, deduplication uses the global enabled setting
        # Since it's enabled by default, deduplication still happens
        first_blob = ActiveStorage::Blob.build_after_unfurling(
          io: StringIO.new(test_file_content),
          filename: filename
        )
        first_blob.save!

        test_io.rewind
        second_blob = ActiveStorage::Blob.build_after_unfurling(
          io: test_io,
          filename: filename
        )

        # Should reuse the existing blob since global deduplication is enabled
        expect(second_blob.id).to eq(first_blob.id)
        expect(ActiveStorage::Blob.count).to eq(1)
      end
    end
  end

  describe ".create_before_direct_upload!" do
    context "when deduplication is enabled" do
      let(:user) { User.create!(name: "Test User") }
      let(:checksum) { Digest::MD5.base64digest(test_file_content) }

      it "creates a new blob if no duplicate exists" do
        expect {
          blob = ActiveStorage::Blob.create_before_direct_upload!(
            filename: filename,
            byte_size: test_file_content.bytesize,
            checksum: checksum,
            content_type: "text/plain",
            __dedup_record: user,
            __dedup_attachment_name: :avatar
          )
          expect(blob).to be_persisted
        }.to change { ActiveStorage::Blob.count }.by(1)
      end

      it "reuses existing blob with same checksum and service" do
        # Create initial blob
        first_blob = ActiveStorage::Blob.create_before_direct_upload!(
          filename: filename,
          byte_size: test_file_content.bytesize,
          checksum: checksum,
          content_type: "text/plain",
          service_name: service_name,
          __dedup_record: user,
          __dedup_attachment_name: :avatar
        )

        # Try to create another with same checksum
        second_blob = ActiveStorage::Blob.create_before_direct_upload!(
          filename: filename,
          byte_size: test_file_content.bytesize,
          checksum: checksum,
          content_type: "text/plain",
          service_name: service_name,
          __dedup_record: user,
          __dedup_attachment_name: :avatar
        )

        expect(second_blob.id).to eq(first_blob.id)
        expect(ActiveStorage::Blob.count).to eq(1)
      end
    end
  end

  describe ".create_after_unfurling!" do
    context "when deduplication is enabled" do
      let(:user) { User.create!(name: "Test User") }

      it "creates a new blob if no duplicate exists" do
        expect {
          blob = ActiveStorage::Blob.create_after_unfurling!(
            io: StringIO.new(test_file_content),
            filename: filename,
            __dedup_record: user,
            __dedup_attachment_name: :avatar
          )
          expect(blob).to be_persisted
        }.to change { ActiveStorage::Blob.count }.by(1)
      end

      it "reuses existing blob with same checksum" do
        # Create initial blob
        first_blob = ActiveStorage::Blob.create_after_unfurling!(
          io: StringIO.new(test_file_content),
          filename: filename,
          __dedup_record: user,
          __dedup_attachment_name: :avatar
        )

        # Try to create another with same content
        second_blob = ActiveStorage::Blob.create_after_unfurling!(
          io: StringIO.new(test_file_content),
          filename: filename,
          __dedup_record: user,
          __dedup_attachment_name: :avatar
        )

        expect(second_blob.id).to eq(first_blob.id)
        expect(ActiveStorage::Blob.count).to eq(1)
      end
    end
  end
end
