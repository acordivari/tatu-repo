# Downloads a post's Instagram image and stores it via Active Storage so the
# app never depends on Instagram's expiring CDN URLs at render time.
class AttachPostImageJob < ApplicationJob
  queue_as :images

  # IG CDN URLs expire; if the download 404s we just skip — the post still
  # exists and can be re-ingested later.
  discard_on ActiveStorage::IntegrityError

  def perform(post_id)
    post = Post.find_by(id: post_id)
    return if post.nil? || post.image.attached? || post.image_url.blank?

    response = HTTParty.get(post.image_url, timeout: 15, follow_redirects: true)
    return unless response.success?

    content_type = response.headers["content-type"].presence || "image/jpeg"
    return unless content_type.start_with?("image/")

    post.image.attach(
      io: StringIO.new(response.body),
      filename: "#{post.ig_shortcode}.jpg",
      content_type: content_type
    )
  rescue HTTParty::Error, SocketError, Timeout::Error, Net::OpenTimeout => e
    Rails.logger.warn("[AttachPostImageJob] post=#{post_id} failed: #{e.class} #{e.message}")
  end
end
