module Api
  module V1
    class ArtistsController < BaseController
      # GET /api/v1/artists?q=&country=&region=&located=&sort=
      def index
        artists = Artist.all
        artists = artists.search(params[:q])               if params[:q].present?
        artists = artists.in_country(params[:country])     if params[:country].present?
        artists = artists.in_region(params[:region])       if params[:region].present?
        artists = artists.located                          if params[:located] == "true"
        artists = sort(artists)

        records = paginate(artists).includes(posts: { image_attachment: :blob })
        render json: records.map { |a| ArtistSerializer.new(a).as_card }
      end

      # GET /api/v1/artists/:id  (id may be a numeric id or a handle)
      def show
        artist = find_artist
        posts = artist.posts.recent.limit(60)
        render json: ArtistSerializer.new(artist).as_detail(posts: posts)
      end

      # GET /api/v1/artists/map?sw_lat=&sw_lng=&ne_lat=&ne_lng=
      def map
        artists = Artist.located
        if %i[sw_lat sw_lng ne_lat ne_lng].all? { |k| params[k].present? }
          artists = artists.within_bounds(
            params[:sw_lat].to_f, params[:sw_lng].to_f,
            params[:ne_lat].to_f, params[:ne_lng].to_f
          )
        end
        render json: artists.limit(2000).map { |a| ArtistSerializer.new(a).as_marker }
      end

      # GET /api/v1/artists/regions — facet counts for filter UI.
      def regions
        render json: {
          countries: Artist.where.not(country: nil).group(:country).order(Arel.sql("COUNT(*) DESC")).count,
          regions:   Artist.where.not(region: nil).group(:region).order(Arel.sql("COUNT(*) DESC")).count
        }
      end

      private

      def find_artist
        if params[:id].to_s.match?(/\A\d+\z/)
          Artist.find(params[:id])
        else
          Artist.find_by!(handle: Artist.normalize_handle(params[:id]))
        end
      end

      def sort(scope)
        case params[:sort]
        when "name"   then scope.order(Arel.sql("COALESCE(name, handle) ASC"))
        when "recent" then scope.order(updated_at: :desc)
        else scope.order(posts_count: :desc, handle: :asc) # most-featured first
        end
      end
    end
  end
end
