# frozen_string_literal: true

RSpec.describe ActiveStorageDedup do
  it "has a version number" do
    expect(ActiveStorageDedup::VERSION).not_to be nil
  end

  it "is configured correctly" do
    expect(ActiveStorageDedup.configuration).to be_a(ActiveStorageDedup::Configuration)
  end
end
