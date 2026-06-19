class UsersController < ApplicationController
  before_action :logged_in?, only: [:show, :edit]

  def index
    @users = User.all
  end


  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)

    if @user.save

      login(@user)
      redirect_to root_path
  else

    flash[:error]= @user.errors.full_messages
    render :new
  end
end


  def show
    @user = User.find_by_id(params[:id])
  end

  def edit
    user_id = params[:id]
    @user = User.find_by_id(user_id)
  end

  def update
    user_id = params[:id]
    @user = User.find_by_id(user_id)
    @user.update_attributes(user_params)
    redirect_to user_path(@user)
  end

  def destroy
    @user = User.find_by_id params[:id]
    @user.destroy
    redirect_to root_path
  end

  private
  def user_params
    params.require(:user).permit(:full_name, :current_city, :email, :password)
  end

  def user_id
    params[:id]
  end
end
