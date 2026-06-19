module Api
  module V1
    class BaseController < ActionController::API
      rescue_from ActiveRecord::RecordNotFound, with: :not_found

      DEFAULT_PER_PAGE = 24
      MAX_PER_PAGE = 60

      private

      def not_found
        render json: { error: "Not found" }, status: :not_found
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
