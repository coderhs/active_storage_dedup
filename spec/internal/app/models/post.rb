# frozen_string_literal: true

class Post < ActiveRecord::Base
  has_one_attached :cover_image
  has_many_attached :images
end
