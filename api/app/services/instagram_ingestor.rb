# Ingests scraped Instagram posts into Artist + Post records.
#
# Accepts an array of post hashes shaped like Apify's Instagram Scraper output
# (https://apify.com/apify/instagram-scraper). Field names are normalized
# leniently so the same code path works for live Apify runs and for fixture
# JSON dumped to disk.
#
# For each post it:
#   1. upserts the Post by its Instagram shortcode (idempotent re-runs),
#   2. parses "tattoo by @handle" from the caption to find/create the Artist,
#   3. enqueues image download (Active Storage) so we never hotlink the
#      expiring CDN URL.
class InstagramIngestor
  Result = Struct.new(:posts_created, :posts_updated, :artists_created, :unattributed, keyword_init: true)

  # attribute_by: :caption parses "tattoo by @handle" (aggregator reposts);
  #               :owner attributes the post to the account it was scraped from
  #               (an artist's own posts, which never credit themselves).
  # create_missing: whether owner-attribution may create a new Artist for an
  # unseen owner. False for fetch_work — a scraped gallery can contain
  # collaborative posts owned by tagged studios/conventions we don't track,
  # and we don't want those slipping past the review gate.
  def initialize(items, attach_images: true, attribute_by: :caption,
                 source_account: "blackworkers", create_missing: true)
    @items = Array(items)
    @attach_images = attach_images
    @attribute_by = attribute_by
    @source_account = source_account
    @create_missing = create_missing
    @result = Result.new(posts_created: 0, posts_updated: 0, artists_created: 0, unattributed: 0)
  end

  def call
    @items.each { |raw| ingest_one(normalize(raw)) }
    @result
  end

  private

  def ingest_one(item)
    return if item[:shortcode].blank?

    artist = @attribute_by == :owner ? resolve_owner(item[:owner]) : resolve_artist(item[:caption])
    # In owner mode, skip posts whose owner we don't track (collaborative/tagged
    # posts) rather than orphaning them or auto-creating junk artists.
    return if @attribute_by == :owner && artist.nil?

    @result.unattributed += 1 if artist.nil?

    post = Post.find_or_initialize_by(ig_shortcode: item[:shortcode])
    new_record = post.new_record?

    post.assign_attributes(
      caption:    item[:caption],
      source_url: item[:url],
      image_url:  item[:image_url],
      posted_at:  item[:posted_at],
      artist:     artist
    )
    post.save!

    new_record ? (@result.posts_created += 1) : (@result.posts_updated += 1)
    AttachPostImageJob.perform_later(post.id) if @attach_images && item[:image_url].present? && !post.image.attached?
  end

  def resolve_artist(caption)
    handle = Post.handle_from_caption(caption)
    return nil if handle.blank?

    artist = Artist.find_or_initialize_by(handle: handle)
    if artist.new_record?
      artist.save!
      @result.artists_created += 1
      # Enrichment (per-artist profile scrape -> bio/location -> geocode) is an
      # explicit, separately-billed step. Run `rake instagram:enrich` when ready.
    end
    artist
  end

  # Attribute a post to the artist whose account it was scraped from.
  def resolve_owner(owner_handle)
    handle = Artist.normalize_handle(owner_handle)
    return nil if handle.blank?

    artist = Artist.find_by(handle: handle)
    return artist if artist
    return nil unless @create_missing

    artist = Artist.create!(handle: handle, sources: [@source_account])
    @result.artists_created += 1
    artist
  end

  # Map varied Apify/fixture key names onto our canonical keys.
  def normalize(raw)
    h = raw.with_indifferent_access
    {
      shortcode:  h[:shortCode] || h[:shortcode] || shortcode_from_url(h[:url]),
      caption:    h[:caption] || h[:text],
      url:        h[:url] || h[:postUrl],
      image_url:  h[:displayUrl] || h[:imageUrl] || h[:image_url] || first_image(h[:images]),
      posted_at:  parse_time(h[:timestamp] || h[:takenAt] || h[:posted_at]),
      owner:      h[:ownerUsername] || h[:owner_username] || h.dig(:owner, :username)
    }
  end

  def shortcode_from_url(url)
    url.to_s[%r{/p/([^/?]+)}, 1]
  end

  def first_image(images)
    Array(images).first
  end

  def parse_time(value)
    return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
    return Time.zone.at(value) if value.is_a?(Numeric)

    Time.zone.parse(value.to_s) if value.present?
  rescue ArgumentError
    nil
  end
end
