# JSON shape for the SPA's shop directory and shop pages.
class ShopSerializer
  include Rails.application.routes.url_helpers

  def initialize(shop)
    @shop = shop
  end

  # Compact card for the shop directory and for linking from artist pages.
  def as_card
    {
      id:              @shop.id,
      handle:          @shop.handle,
      name:            display_name,
      city:            @shop.city,
      region:          @shop.region,
      country:         @shop.country,
      instagram_url:   @shop.instagram_url,
      business_status: @shop.business_status,
      members_count:   @shop.memberships_count,
      located:         @shop.latitude.present?
    }
  end

  # Full shop page: location + the roster of artists who work there.
  def as_detail
    as_card.merge(
      address:    @shop.address_raw,
      latitude:   @shop.latitude,
      longitude:  @shop.longitude,
      maps_url:   maps_url,
      artists:    roster
    )
  end

  private

  def display_name
    @shop.name.presence || "@#{@shop.handle}"
  end

  # A deep link to the verified Google Places listing (or a coordinate search)
  # so visitors can find the studio's real address/hours to book through.
  def maps_url
    if @shop.google_place_id.present?
      "https://www.google.com/maps/search/?api=1&query=#{CGI.escape(display_name)}" \
        "&query_place_id=#{@shop.google_place_id}"
    elsif @shop.latitude.present?
      "https://www.google.com/maps/search/?api=1&query=#{@shop.latitude},#{@shop.longitude}"
    end
  end

  # Current residents first, then by membership confidence. Relies on the
  # controller preloading memberships -> artist -> posts to avoid N+1s.
  def roster
    @shop.memberships
         .sort_by { |m| [m.current ? 0 : 1, -(m.confidence || 0)] }
         .map { |m| ArtistSerializer.new(m.artist).as_card.merge(role: m.role, current: m.current) }
  end
end
