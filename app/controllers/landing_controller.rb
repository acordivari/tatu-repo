class LandingController < ApplicationController

  def index
    @posts = Post.all.order(created_at: :desc)
  end

  def create
    if Favorite.create(favorited: @post, user: current_user)
      redirect_to @post, notice: 'Post has been favorited'
    else
      redirect_to @post, alert: 'Something went wrong...*sad panda*'
    end
  end

  def destroy
    Favorite.where(favorited_id: @post.id, user_id: current_user.id).first.destroy
    redirect_to @post, notice: 'Post is no longer in favorites'
  end

  private

  def set_post
    @post = Post.find_by(params[:post_id] || params[:id])
  end
end
