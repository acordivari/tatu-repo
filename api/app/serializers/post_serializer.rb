class PostSerializer
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

  # Card-sized rendition served straight from storage (see ImageUrls).
  def image_url
    ImageUrls.post_image_url(@post)
  end
end
