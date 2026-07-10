module Api
  module V1
    class ShopsController < BaseController
      before_action :cache_publicly

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
        shop = Shop.includes(memberships: { artist: { posts: Post::IMAGE_EAGER_LOAD } })
                   .find(find_shop_id)
        render json: ShopSerializer.new(shop).as_detail(nearby: nearby_shops(shop))
      end

      private

      # Other located studios in the same city (and country — "Paris" exists on
      # two continents), most-staffed first, for the shop page's discovery strip.
      def nearby_shops(shop)
        return Shop.none if shop.city.blank?

        scope = Shop.located.where.not(id: shop.id)
                    .where("LOWER(city) = ?", shop.city.downcase)
        scope = scope.where("LOWER(country) = ?", shop.country.downcase) if shop.country.present?
        scope.order(memberships_count: :desc, name: :asc).limit(6)
      end

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
