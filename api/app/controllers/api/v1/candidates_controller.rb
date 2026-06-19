module Api
  module V1
    class CandidatesController < BaseController
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
