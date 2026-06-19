class User < ApplicationRecord
  has_secure_password

  has_many :favorites
  has_many :favorite_posts, through: :favorites, source: :favorited, source_type: 'Post'

  has_many :posts


  validates :full_name, presence: true
  validates :email, presence: true, uniqueness: true

end


def self.confirm(params)
  @user = User.find_by({email: params[:email]})
  @user.try(:authenticate, params[:password])
end
