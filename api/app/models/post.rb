class Post < ApplicationRecord
  # Optional: a post may be ingested before (or without) a parseable artist.
  belongs_to :artist, optional: true, counter_cache: true

  # Stored copy of the image so the site never depends on Instagram's
  # expiring CDN URLs. image_url is kept only as the original source.
  has_one_attached :image

  validates :ig_shortcode, presence: true, uniqueness: true

  scope :recent,     -> { order(posted_at: :desc, id: :desc) }
  scope :attributed, -> { where.not(artist_id: nil) }
  # Posts that have a source image URL but no stored copy yet.
  scope :needs_image, -> { where.not(image_url: nil).where.missing(:image_attachment) }

  # The canonical "tattoo by @handle" attribution pattern used by the
  # @blackworkers feed. Tolerates "tattoo/tattoos/tat by", an optional
  # leading @, and surrounding punctuation/emoji.
  # The @blackworkers feed credits the artist with a tattoo-specific lead-in
  # followed by "by @handle". We match a known credit word (not generic verbs
  # like "inspired"/"commissioned") to avoid mis-attributing the wrong handle.
  ATTRIBUTION_PATTERN = /
    \b
    (?:
      tat(?:too?)?s?               # tattoo, tattoos, tat
      | cover[\s\-]?ups?           # cover-up, coverup, cover up
      | bodysuits?                 # bodysuit by @x
      | collab(?:oration)?s?       # collaboration by @x
      | piece | freehand | lettering | linework | dotwork | design | healed
    )
    (?:\s+tattoos?)?               # optional "tattoo", e.g. "healed tattoo by"
    (?:\s*\([^)]*\))?              # optional parenthetical, e.g. "Tattoo (filler) by"
    \s+ by \s* :? \s* @?           # "by", optional colon, optional @
    ([a-z0-9._]{1,30})            # the handle
  /ix

  # Extracts the artist handle from a caption, or nil if none is present.
  def self.handle_from_caption(caption)
    return nil if caption.blank?

    match = caption.match(ATTRIBUTION_PATTERN)
    Artist.normalize_handle(match[1]) if match
  end

  def shortcode_url
    source_url.presence || "https://www.instagram.com/p/#{ig_shortcode}/"
  end
end
