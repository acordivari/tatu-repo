module Api
  module V1
    class ShopsController < BaseController
      # GET /api/v1/shops?q=&country=  — browsable directory (located shops only,
      # most-staffed first).
      def index
        shops = Shop.located
        shops = shops.where("LOWER(country) = ?", params[:country].to_s.downcase) if params[:country].present?
        shops = shops.search(params[:q]) if params[:q].present?
        shops = shops.order(memberships_count: :desc, name: :asc)

        render json: paginate(shops).map { |s| ShopSerializer.new(s).as_card }
      end

      # GET /api/v1/shops/:id  (id may be a numeric id or a handle)
      def show
        shop = Shop.includes(memberships: { artist: { posts: { image_attachment: :blob } } })
                   .find(find_shop_id)
        render json: ShopSerializer.new(shop).as_detail
      end

      private

      def find_shop_id
        if params[:id].to_s.match?(/\A\d+\z/)
          params[:id]
        else
          Shop.where(handle: Artist.normalize_handle(params[:id])).pick(:id) ||
            raise(ActiveRecord::RecordNotFound)
        end
      end
    end
  end
end
