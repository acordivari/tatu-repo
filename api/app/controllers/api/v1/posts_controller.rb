module Api
  module V1
    class PostsController < BaseController
      # GET /api/v1/posts?artist=&attributed=
      def index
        posts = Post.includes(:artist).recent
        posts = posts.attributed if params[:attributed] == "true"
        if params[:artist].present?
          handle = Artist.normalize_handle(params[:artist])
          posts = posts.where(artist: Artist.where(handle: handle))
        end

        records = paginate(posts)
        render json: records.map { |p| PostSerializer.new(p).as_card }
      end

      # GET /api/v1/posts/:id  (id may be a numeric id or a shortcode)
      def show
        post =
          if params[:id].to_s.match?(/\A\d+\z/)
            Post.find(params[:id])
          else
            Post.find_by!(ig_shortcode: params[:id])
          end
        render json: PostSerializer.new(post).as_card
      end
    end
  end
end
