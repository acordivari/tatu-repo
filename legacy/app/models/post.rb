class Post < ApplicationRecord
  belongs_to :artist
  belongs_to :user, optional: true
  has_many :favorites, as: :favorited
  has_many :fans, through: :favorites, source: :user

  end
