class ArtistsController < ApplicationController

  def index
    @artists = Artist.all
    @posts = Post.all

  end

  def new
    @artist = Artist.new
  end

  def show
    @artist = Artist.find_by_id(params[:id])
  end

end
