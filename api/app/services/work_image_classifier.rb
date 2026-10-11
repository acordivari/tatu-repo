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
  VERSION = "haiku45-v5"

  # Longest edge sent to the model. Image tokens scale with pixels (~w*h/750),
  # and 512px is comfortably enough to tell a tattoo from a flyer while costing
  # roughly a third less than the stored 640px card variant.
  MAX_EDGE = 512

  # v5 split the old "work" into what is ON SKIN and what is drawn to be
  # tattooed: both are the artist's work and both stay in galleries, but only a
  # tattoo should front the artist on the homepage. "work" verdicts from v1-v4
  # remain valid (see Post::WORK_KINDS) until re-checked.
  KINDS = %w[tattoo design person promo other].freeze

  INSTRUCTIONS = <<~TXT.freeze
    You are sorting images from tattoo artists' Instagram accounts for a
    directory that only shows their WORK.

    Reply with ONLY a JSON object: {"kind": "...", "confidence": 0.0-1.0}

    "kind" must be exactly one of:
      "tattoo" - a tattoo on skin: fresh, healed, or in progress (a stencil on
                 skin, or a tattoo being made, counts). Lettering and script
                 tattoos count. A person may be visible, as long as the tattoo
                 is the subject.
      "design" - drawn art made to be tattooed, not on skin: a flash sheet, a
                 design or sketch on paper or a tablet, a stencil on paper, a
                 drawing in progress.
      "person" - a PHOTOGRAPH whose subject is a real person rather than a
                 tattoo: a selfie, a portrait, a mirror photo, a lifestyle or
                 holiday snapshot, the artist at work, or a frame from a
                 talking-to-camera video. Still "person" when the people shown
                 happen to have tattoos, and when the image carries caption text.
      "promo"  - no real subject, just a message: a flyer, poster, price list,
                 booking announcement, flash-day advert, meme, screenshot of an
                 app or chat, product advert, merchandise, or a card of text.
      "other"  - none of the above: studio interiors, equipment, pets, food,
                 scenery, and art in other media — a painting on canvas, a
                 mural, a painted object (a helmet, a jacket, a skateboard), a
                 sculpture or a print that is not a tattoo design.

    Judge the SUBJECT of the photo, not whether tattoos appear anywhere in it.
    A mirror selfie of a heavily tattooed artist is "person", not "tattoo".

    SHOWING A TATTOO IS "tattoo". When someone poses so a tattoo can be seen —
    a sleeve held out, a back, chest, belly or leg piece turned to the camera,
    a healed piece on a client — the tattoo is the reason for the photo, so it
    is "tattoo" even with their face, outfit and surroundings in frame. Call it
    "person" only when the photo is about the person and any tattoo is
    incidental.

    DRAWN ART MADE TO BE TATTOOED IS "design", whatever it depicts. A drawing
    of a face, a figure, a skull or an animal is the artist's design — never
    "person". A design on a plain or paper background is a flash sheet — never
    "promo". Only call it "promo" if the image exists to carry a message
    (dates, prices, an announcement, a logo, merchandise for sale) rather than
    to show a design someone could be tattooed with.

    PAINTINGS ARE "other". A finished painting on canvas, a wall or an object
    is art in another medium, even when the artist made it and even in their
    tattoo style. Flash painted on paper as a sheet of designs is still
    "design".

    "confidence" is your certainty, 0.0 to 1.0. Use below 0.6 when genuinely
    unsure — a wrong "person" verdict hides real work, so prefer a low
    confidence over a confident guess.
  TXT

  # Appended when OCR found text in the image. The model sees a 512px copy, at
  # which a poster's dates and "books open" line are often unreadable — so an
  # illustrated tour poster looked like flash and v2's drawn-art rule pulled it
  # back to "work". OCR read the full-size card, so it can see what the model
  # cannot.
  OCR_CONTEXT = <<~TXT.freeze
    TEXT IN THE IMAGE. OCR read this text burned into the image (it may be
    partial or misread):
    """
    %<text>s
    """
    Use it to tell a message from a design. Dates, prices, "books open",
    "booking", "guest spot", tour cities, event names, discount codes or
    product names mean the image exists to carry a message, so it is "promo"
    even when it is illustrated. A signature, an @handle watermark, a short
    title, or lettering that is itself the tattoo design does not make an
    image "promo".
  TXT

  # Long enough for a flyer's key lines; past this it is token cost, not signal.
  OCR_MAX_CHARS = 400

  # Haiku 4.5 pricing ($/million tokens) for cost reporting.
  PRICE_IN = 1.0
  PRICE_OUT = 5.0

  Verdict = Struct.new(:kind, :confidence, keyword_init: true) do
    def work? = Post::WORK_KINDS.include?(kind)
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

  # Classify one image given its JPEG bytes and any OCR text read from it.
  # Returns a Verdict, or nil if the call failed or the model returned
  # something unusable — callers must treat nil as "unknown" and leave the post
  # alone rather than defaulting it to a kind, which would quietly mislabel work.
  def classify(jpeg_bytes, ocr_text: nil)
    message = @client.messages.create(
      model: @model,
      max_tokens: 128,
      messages: [ {
        role: "user",
        content: [
          { type: "image",
            source: { type: "base64", media_type: "image/jpeg",
                      data: Base64.strict_encode64(jpeg_bytes) } },
          { type: "text", text: self.class.prompt(ocr_text) }
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

  # The instructions, plus the OCR block when there is text worth reading.
  # Whitespace is collapsed because OCR emits one line per detected box.
  def self.prompt(ocr_text)
    text = ocr_text.to_s.squish.truncate(OCR_MAX_CHARS)
    return INSTRUCTIONS if text.blank?

    INSTRUCTIONS + "\n" + format(OCR_CONTEXT, text: text)
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
