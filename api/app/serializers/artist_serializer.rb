# Plain-Ruby serializers (no gem) — explicit JSON shape for the SPA.
class ArtistSerializer
  include Rails.application.routes.url_helpers

  def initialize(artist)
    @artist = artist
  end

  # Compact card representation for grids and search results.
  def as_card
    {
      id:            @artist.id,
      handle:        @artist.handle,
      name:          @artist.name,
      shop_name:     @artist.shop_name,
      city:          @artist.city,
      region:        @artist.region,
      country:       @artist.country,
      latitude:      @artist.latitude,
      longitude:     @artist.longitude,
      posts_count:   @artist.posts_count,
      instagram_url: @artist.instagram_url,
      preview_image_url: preview_image_url
    }
  end

  # Full representation for the artist detail page (includes recent posts).
  def as_detail(posts: [])
    as_card.merge(
      bio:          @artist.bio,
      website:      @artist.website,
      location_raw: @artist.location_raw,
      posts:        posts.map { |p| PostSerializer.new(p).as_card }
    )
  end

  # Thumbnail for the directory: the artist's most recent post image.
  # Relies on the controller preloading :posts to avoid N+1 queries.
  def preview_image_url
    post = @artist.posts.max_by { |p| p.posted_at || p.created_at }
    return nil if post.nil?

    post.image.attached? ? rails_blob_url(post.image) : post.image_url
  end

  # Minimal marker for the map.
  def as_marker
    {
      id:        @artist.id,
      handle:    @artist.handle,
      name:      @artist.name,
      city:      @artist.city,
      region:    @artist.region,
      country:   @artist.country,
      latitude:  @artist.latitude,
      longitude: @artist.longitude
    }
  end
end
