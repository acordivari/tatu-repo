class Post < ApplicationRecord
  # Optional: a post may be ingested before (or without) a parseable artist.
  belongs_to :artist, optional: true, counter_cache: true

  # Stored copy of the image so the site never depends on Instagram's
  # expiring CDN URLs. image_url is kept only as the original source.
  # :card is the grid-tile rendition the SPA actually displays (~640px covers
  # 2x-retina tiles); originals stay in storage but are never served to lists.
  has_one_attached :image do |attachable|
    attachable.variant :card, resize_to_limit: [ 640, 640 ], preprocessed: true
  end

  # Eager-load spec that lets serializers build variant image URLs without
  # per-record queries. Nest it under artist preloads as Post::IMAGE_EAGER_LOAD.
  IMAGE_EAGER_LOAD = { image_attachment: { blob: { variant_records: { image_attachment: :blob } } } }.freeze
  scope :with_image_blobs, -> { includes(IMAGE_EAGER_LOAD) }

  validates :ig_shortcode, presence: true, uniqueness: true

  scope :recent,     -> { order(posted_at: :desc, id: :desc) }
  scope :attributed, -> { where.not(artist_id: nil) }
  # Posts that have a source image URL but no stored copy yet.
  scope :needs_image, -> { where.not(image_url: nil).where.missing(:image_attachment) }

  # An overlay is recognised by the SHAPE of its text, not the amount. Rendered
  # captions and UI chrome are wide, short lines; lettering tattooed on skin is
  # a few tall, chunky ones. Judging on area alone flags script tattoos as junk
  # — on a production sample "THERE BETTER BE DOGS" and "Lola" scored higher
  # area than an Instagram year-in-review screenshot.
  OVERLAY_ELONGATION = 6.0   # mean line width/height; overlays 10-12, tattoos 1-2
  OVERLAY_MAX_HEIGHT = 0.06  # mean line height; overlays 0.02-0.04, tattoos 0.10+
  # Volume thresholds exist to spare WATERMARKED WORK. Shape alone flags an
  # artist's own signature ("@familyinktattoo", "REBECCA BONACI") and short
  # captions on genuine photos ("Over 3yrs healed") — 365 of them in prod, all
  # real work. Flyers, booking notices and screenshots carry several wordy
  # lines; a signature carries one short one.
  OVERLAY_MIN_CHARS  = 40
  OVERLAY_MIN_LINES  = 3

  # Stored image, not yet OCR'd. The image blob is immutable once attached, so
  # a null stamp is the whole condition — there is no "re-OCR when the source
  # changed" case to miss.
  scope :needs_ocr, -> { where(ocr_at: nil).where.associated(:image_attachment) }
  scope :ocr_done,  -> { where.not(ocr_at: nil) }
  # Burned-in caption/UI text: the OCR-visible half of "not this artist's work".
  # Deliberately says nothing about text-free personal photos (a selfie, a
  # holiday snap) — OCR is blind to those and only the vision pass sees them.
  scope :text_overlay, lambda {
    ocr_done
      .where(ocr_elongation: OVERLAY_ELONGATION..)
      .where(ocr_mean_height: ...OVERLAY_MAX_HEIGHT)
      .where(ocr_lines: OVERLAY_MIN_LINES..)
      .where("length(ocr_text) >= ?", OVERLAY_MIN_CHARS)
  }

  scope :classified,   -> { where.not(classified_at: nil) }
  scope :unclassified, -> { where(classified_at: nil) }
  # Stale once the classifier changes: a new prompt or model can reach a
  # different verdict, so the stamp alone must never decide what to skip.
  scope :classifier_stale, lambda { |version|
    where(classified_at: nil).or(where.not(classifier_version: version))
  }
  scope :of_kind, ->(kind) { where(content_kind: kind) }

  # Images the directory should not show: an overlay by OCR, or judged not to
  # be work by the vision pass. Kept as one place so the site and the review
  # tooling cannot disagree about what is hidden.
  scope :not_work, lambda {
    text_overlay.or(where(content_kind: %w[person promo other]))
  }

  # Same judgement as the scope, for callers holding raw OCR output rather than
  # a persisted row. Kept beside the scope so the two cannot drift.
  def self.overlay_shape?(elongation:, mean_height:, lines:, text:)
    elongation.to_f >= OVERLAY_ELONGATION &&
      mean_height.to_f < OVERLAY_MAX_HEIGHT &&
      lines.to_i >= OVERLAY_MIN_LINES &&
      text.to_s.length >= OVERLAY_MIN_CHARS
  end

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
