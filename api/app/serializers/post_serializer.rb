class PostSerializer
  include Rails.application.routes.url_helpers

  def initialize(post)
    @post = post
  end

  def as_card
    {
      id:           @post.id,
      shortcode:    @post.ig_shortcode,
      image_url:    image_url,
      source_url:   @post.shortcode_url,
      caption:      @post.caption,
      posted_at:    @post.posted_at,
      artist_id:    @post.artist_id,
      artist_handle: @post.artist&.handle
    }
  end

  private

  # Prefer the stored Active Storage copy; fall back to the (expiring)
  # original CDN URL if the download hasn't completed yet.
  def image_url
    if @post.image.attached?
      rails_blob_url(@post.image)
    else
      @post.image_url
    end
  end
end
