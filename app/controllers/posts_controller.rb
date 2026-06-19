class PostsController < ApplicationController
  before_action :set_post, only: [:show, :edit, :update, :destroy]
  before_action :correct_user, only: [:show, :edit, :update, :destroy]


  def index
    @posts = Post.all.order(created_at: :desc)
    if params[:search]

    @posts = Post.where(Instagram: params[:search])
    # render "posts/show.html.erb"
    else
      @posts = Post.all.order("created_at DESC")
    end
  end

  def show
    @post = Post.find_by_id(params[:id])
    @user = User.find_by_id(@post.user_id)
  end


  def favorites
    @posts = current_user.favorite_posts
  end

private

  def set_post
    @post = Post.find_by(id: params[:id])
  end

  def correct_user
    @post = current_user.posts.find_by(id: params[:id])
    redirect_to posts_path, notice: "Not authorized to edit this post" if @post.nil?
  end

end
