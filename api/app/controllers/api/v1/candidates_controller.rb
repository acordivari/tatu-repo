module Api
  module V1
    class CandidatesController < BaseController
      before_action :require_admin!

      # GET /api/v1/candidates — the review queue (borderline classifications).
      def index
        candidates = ArtistCandidate.review.order(Arel.sql("confidence DESC NULLS LAST"), id: :asc)
        render json: {
          count: candidates.size,
          candidates: candidates.map { |c| serialize(c) }
        }
      end

      # POST /api/v1/candidates/:handle/approve
      def approve
        artist = candidate.approve!
        render json: { status: "approved", handle: artist.handle }
      end

      # POST /api/v1/candidates/:handle/reject
      def reject
        candidate.update!(status: "rejected")
        render json: { status: "rejected", handle: candidate.handle }
      end

      private

      # Approving a candidate publishes it to the live directory, so every
      # candidates endpoint requires the shared admin token
      # (Authorization: Bearer <ADMIN_TOKEN>; the /review page prompts for it).
      # With no ADMIN_TOKEN configured, the endpoints are disabled outright.
      def require_admin!
        expected = ENV["ADMIN_TOKEN"].to_s
        provided = request.authorization.to_s.delete_prefix("Bearer ").strip
        return if expected.present? && provided.present? &&
                  ActiveSupport::SecurityUtils.secure_compare(provided, expected)

        render json: { error: "Unauthorized" }, status: :unauthorized
      end

      def candidate
        @candidate ||= ArtistCandidate.find_by!(handle: Artist.normalize_handle(params[:handle]))
      end

      def serialize(c)
        {
          handle:          c.handle,
          name:            c.full_name,
          bio:             c.bio,
          category:        c.category,
          followers_count: c.followers_count,
          posts_count:     c.posts_count,
          confidence:      c.confidence,
          reason:          c.reason,
          instagram_url:   c.instagram_url
        }
      end
    end
  end
end
