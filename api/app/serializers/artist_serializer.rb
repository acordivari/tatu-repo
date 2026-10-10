# Plain-Ruby serializers (no gem) — explicit JSON shape for the SPA.
class ArtistSerializer
  def initialize(artist)
    @artist = artist
  end

  # Show the canonical region label when we have one, so what a user sees
  # matches the value they filtered on (raw `region` stays for provenance).
  def display_region
    @artist.region_canonical.presence || @artist.region
  end

  # Compact card representation for grids and search results. Pass
  # preview_post when the posts are already in hand (see as_detail) to avoid
  # re-walking the posts association.
  def as_card(preview_post: pick_preview(@artist.posts))
    {
      id:            @artist.id,
      handle:        @artist.handle,
      name:          @artist.name,
      shop_name:     @artist.shop_name,
      city:          @artist.city,
      region:        display_region,
      country:       @artist.country,
      latitude:      @artist.latitude,
      longitude:     @artist.longitude,
      posts_count:   @artist.posts_count,
      instagram_url: @artist.instagram_url,
      preview_image_url: preview_post && ImageUrls.post_image_url(preview_post)
    }
  end

  # Full representation for the artist detail page (includes recent posts and
  # the studio(s) the artist works at, so the profile can point visitors to the
  # right shop page for booking). The preview is picked from the same posts, so
  # there is no second pass over the association.
  def as_detail(posts: [])
    posts = posts.to_a # one load — pick_preview must not issue its own query
    as_card(preview_post: pick_preview(posts)).merge(
      bio:          @artist.bio,
      website:      @artist.website,
      location_raw: @artist.location_raw,
      shops:        artist_shops,
      posts:        posts.map { |p| PostSerializer.new(p).as_card }
    )
  end

  # The artist's shop memberships, primary studio first, then current ones, then
  # by confidence. Each entry links to its shop page and carries the role.
  def artist_shops
    @artist.memberships
           .sort_by { |m| [m.shop_id == @artist.primary_shop_id ? 0 : 1, m.current ? 0 : 1, -(m.confidence || 0)] }
           .map do |m|
             shop = m.shop
             {
               handle:          shop.handle,
               name:            shop.name.presence || "@#{shop.handle}",
               city:            shop.city,
               region:          shop.region,
               country:         shop.country,
               instagram_url:   shop.instagram_url,
               business_status: shop.business_status,
               located:         shop.latitude.present?,
               role:            m.role,
               current:         m.current,
               primary:         m.shop_id == @artist.primary_shop_id
             }
           end
  end

  # The directory thumbnail (also the link-unfurl image): the newest post known
  # to be work — a vision "work" verdict or a curated credit — else the newest
  # post not judged junk. Plain newest-first put artists' latest selfies and
  # booking cards on the homepage once their own feeds were backfilled.
  # Relies on the controller preloading :posts to avoid N+1 queries.
  def pick_preview(posts)
    shown = posts.reject(&:not_work?)
    vouched = shown.select { |p| p.content_kind == "work" || p.credited_to?(@artist) }
    vouched.max_by(&:recency) || shown.max_by(&:recency)
  end

  # Minimal marker for the map.
  def as_marker
    {
      id:        @artist.id,
      handle:    @artist.handle,
      name:      @artist.name,
      city:      @artist.city,
      region:    display_region,
      country:   @artist.country,
      latitude:  @artist.latitude,
      longitude: @artist.longitude
    }
  end
end
