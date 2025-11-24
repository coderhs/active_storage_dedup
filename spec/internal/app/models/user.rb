# frozen_string_literal: true

class User < ActiveRecord::Base
  has_one_attached :avatar
  has_many_attached :documents
end
