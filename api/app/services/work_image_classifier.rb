# Decides whether a scraped image actually shows the artist's tattoo work, or
# is a personal photo, a promo card, or something else entirely.
#
# This is the layer OCR cannot be: OCR reads burned-in text, so it catches
# flyers and caption overlays but is blind to a text-free selfie or holiday
# snap — 18,404 of our images carry no detectable text at all. It also cannot
# tell a large-type promo card from a lettering tattoo, since both are simply
# "text". A vision model sees the picture.
#
# Configure with ANTHROPIC_API_KEY (api/.env). Images are sent one per request:
# batching several into one message saves ~17% of tokens but makes the model
# reason about them together, which is a poor trade when the whole point is a
# per-image verdict.
class WorkImageClassifier
  class NotConfigured < StandardError; end

  MODEL = :"claude-haiku-4-5"

  # Bumped whenever the prompt, categories, or model change, so a re-run can
  # find verdicts produced by an older classifier instead of trusting the stamp.
  VERSION = "haiku45-v1"

  # Longest edge sent to the model. Image tokens scale with pixels (~w*h/750),
  # and 512px is comfortably enough to tell a tattoo from a flyer while costing
  # roughly a third less than the stored 640px card variant.
  MAX_EDGE = 512

  KINDS = %w[work person promo other].freeze

  INSTRUCTIONS = <<~TXT.freeze
    You are sorting images from tattoo artists' Instagram accounts for a
    directory that only shows their WORK.

    Reply with ONLY a JSON object: {"kind": "...", "confidence": 0.0-1.0}

    "kind" must be exactly one of:
      "work"   - the subject is tattoo art: a tattoo on skin (fresh, healed, or
                 in progress), or the artist's own design, flash sheet, or
                 stencil. Lettering and script tattoos count as work. A person
                 may be visible, as long as the tattoo is the subject.
      "person" - the subject is a person, not a tattoo: a selfie, a portrait, a
                 mirror photo, a lifestyle or holiday snapshot, or a frame from
                 a talking-to-camera video. Still "person" even when the people
                 shown happen to have tattoos, and even when the image carries
                 caption text.
      "promo"  - no real subject, just a message: a flyer, poster, price list,
                 booking announcement, flash-day advert, meme, screenshot of an
                 app or chat, product advert, or a plain card of text.
      "other"  - none of the above: studio interiors, equipment, pets, food,
                 scenery, artwork that is clearly not tattoo-related.

    Judge the SUBJECT of the photo, not whether tattoos appear anywhere in it.
    A mirror selfie of a heavily tattooed artist is "person", not "work".

    "confidence" is your certainty, 0.0 to 1.0. Use below 0.6 when genuinely
    unsure — a wrong "person" verdict hides real work, so prefer a low
    confidence over a confident guess.
  TXT

  # Haiku 4.5 pricing ($/million tokens) for cost reporting.
  PRICE_IN = 1.0
  PRICE_OUT = 5.0

  Verdict = Struct.new(:kind, :confidence, keyword_init: true) do
    def work? = kind == "work"
    def valid? = KINDS.include?(kind)
  end

  attr_reader :input_tokens, :output_tokens

  def initialize(api_key: self.class.api_key, model: MODEL)
    raise NotConfigured, "ANTHROPIC_API_KEY is not set" if api_key.blank?

    require "anthropic"
    @client = Anthropic::Client.new(api_key: api_key)
    @model = model
    @input_tokens = 0
    @output_tokens = 0
    @lock = Mutex.new
  end

  def self.api_key
    ENV["ANTHROPIC_API_KEY"].presence || Rails.application.credentials.dig(:anthropic, :api_key)
  end

  def self.configured? = api_key.present?

  def cost_usd
    (input_tokens / 1_000_000.0 * PRICE_IN) + (output_tokens / 1_000_000.0 * PRICE_OUT)
  end

  # Classify one image given its JPEG bytes. Returns a Verdict, or nil if the
  # call failed or the model returned something unusable — callers must treat
  # nil as "unknown" and leave the post alone rather than defaulting it to a
  # kind, which would quietly mislabel work.
  def classify(jpeg_bytes)
    message = @client.messages.create(
      model: @model,
      max_tokens: 128,
      messages: [ {
        role: "user",
        content: [
          { type: "image",
            source: { type: "base64", media_type: "image/jpeg",
                      data: Base64.strict_encode64(jpeg_bytes) } },
          { type: "text", text: INSTRUCTIONS }
        ]
      } ]
    )
    @lock.synchronize do
      @input_tokens += message.usage.input_tokens
      @output_tokens += message.usage.output_tokens
    end
    parse(message.content.select { |b| b.type == :text }.map(&:text).join)
  rescue Anthropic::Errors::APIError => e
    Rails.logger.warn("[WorkImageClassifier] #{e.class}: #{e.message}")
    nil
  end

  # Downscale before sending: image tokens scale with pixel count, so this is
  # the difference between ~437 and ~280 tokens per image.
  def self.downscale(bytes, max_edge: MAX_EDGE)
    require "mini_magick"
    tmp = Tempfile.new([ "cls", ".jpg" ], binmode: true)
    tmp.write(bytes)
    tmp.flush
    img = MiniMagick::Image.new(tmp.path)
    img.resize("#{max_edge}x#{max_edge}>") if [ img.width, img.height ].max > max_edge
    File.binread(img.path)
  rescue StandardError
    bytes # a resize failure is not worth losing the classification over
  ensure
    tmp&.close!
  end

  private

  def parse(text)
    json = text[/\{.*\}/m]
    return nil if json.blank?

    row = JSON.parse(json)
    v = Verdict.new(kind: row["kind"].to_s.downcase.strip,
                    confidence: row["confidence"]&.to_f)
    v.valid? ? v : nil
  rescue JSON::ParserError
    nil
  end
end
