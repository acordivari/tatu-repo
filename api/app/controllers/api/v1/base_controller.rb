module Api
  module V1
    class BaseController < ActionController::API
      # Lets ImageUrls generate Disk-service URLs in development (S3/R2 URLs
      # need no request context).
      include ActiveStorage::SetCurrent

      rescue_from ActiveRecord::RecordNotFound, with: :not_found

      DEFAULT_PER_PAGE = 24
      MAX_PER_PAGE = 60

      private

      def not_found
        # Don't let cache_publicly's header stick to misses — a just-published
        # artist shouldn't be shadowed by a cached 404.
        expires_now
        render json: { error: "Not found" }, status: :not_found
      end

      # Read-only public data that changes on pipeline cadence (days), not per
      # request — let browsers and any intermediary cache it briefly.
      def cache_publicly
        expires_in 5.minutes, public: true
      end

      # Offset paginate a relation and emit pagination headers for the SPA.
      def paginate(scope)
        page = [params[:page].to_i, 1].max
        per  = params[:per_page].to_i
        per  = DEFAULT_PER_PAGE if per <= 0
        per  = MAX_PER_PAGE if per > MAX_PER_PAGE

        total = scope.except(:order).count
        response.set_header("X-Page", page.to_s)
        response.set_header("X-Per-Page", per.to_s)
        response.set_header("X-Total-Count", total.to_s)
        response.set_header("X-Total-Pages", (total.zero? ? 1 : (total.to_f / per).ceil).to_s)

        scope.limit(per).offset((page - 1) * per)
      end
    end
  end
end
