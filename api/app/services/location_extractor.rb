# Extracts a structured location (city / region / country) from freeform
# Instagram bios using Claude Haiku. Far more accurate than regex on messy
# bios: it reads "🇧🇷 São Paulo / SP" or "tattoo artist @SHOWDOWN (10727 124st)
# Edmonton" correctly and returns nil for non-locations ("Books closed") rather
# than inventing one — which is what made the regex approach geocode wrong.
#
# Configure with ANTHROPIC_API_KEY (api/.env). Bios are batched per request to
# amortize cost; the model returns a JSON array aligned to the input order.
class LocationExtractor
  class NotConfigured < StandardError; end

  MODEL = :"claude-haiku-4-5"
  BATCH_SIZE = 25

  Location = Struct.new(:city, :region, :country, keyword_init: true) do
    def present?
      [city, region, country].any?(&:present?)
    end

    def to_query
      [city, region, country].compact_blank.join(", ").presence
    end
  end

  INSTRUCTIONS = <<~TXT.freeze
    You extract the tattoo artist's primary studio/home location from each Instagram bio.
    Return ONLY a JSON array — one object per bio, in input order, with keys:
      "i": the bio's index number
      "city": city name, or null
      "region": state/province/region, or null
      "country": full country name (e.g. "United States", "Brazil"), or null
    Rules:
    - Use null for any field not clearly stated. If the bio has no location at all, all three are null.
    - Expand flag emoji to the country (🇧🇷 -> Brazil, 🇺🇸 -> United States, 🇰🇷 -> South Korea).
    - Pick ONE primary location if several are listed (the first / home studio).
    - Never treat @handles, emails, URLs, or phrases like "books closed" as locations.
    - Output the JSON array and nothing else.
  TXT

  # Haiku 4.5 pricing ($/million tokens) for cost reporting.
  PRICE_IN = 1.0
  PRICE_OUT = 5.0

  attr_reader :input_tokens, :output_tokens

  def initialize(api_key: self.class.api_key)
    raise NotConfigured, "ANTHROPIC_API_KEY is not set" if api_key.blank?

    require "anthropic"
    @client = Anthropic::Client.new(api_key: api_key)
    @input_tokens = 0
    @output_tokens = 0
  end

  def cost_usd
    (input_tokens / 1_000_000.0 * PRICE_IN) + (output_tokens / 1_000_000.0 * PRICE_OUT)
  end

  def self.api_key
    ENV["ANTHROPIC_API_KEY"].presence || Rails.application.credentials.dig(:anthropic, :api_key)
  end

  def self.configured?
    api_key.present?
  end

  # Extracts locations for an array of bios. Returns an array aligned to the
  # input; each entry is a Location (possibly empty) or nil for blank bios.
  def extract(bios)
    results = Array.new(bios.size)
    bios.each_slice(BATCH_SIZE).with_index do |slice, slice_index|
      offset = slice_index * BATCH_SIZE
      extract_batch(slice).each { |i, loc| results[offset + i] = loc if i.between?(0, slice.size - 1) }
    end
    results
  end

  private

  # Returns a Hash of { index_within_slice => Location }.
  def extract_batch(bios)
    prompt = INSTRUCTIONS + "\n\nBios:\n" +
             bios.each_with_index.map { |b, i| "#{i}: #{b.to_s.gsub(/\s+/, ' ').strip}" }.join("\n")

    message = @client.messages.create(
      model: MODEL,
      max_tokens: 4096,
      messages: [{ role: "user", content: prompt }]
    )
    @input_tokens += message.usage.input_tokens
    @output_tokens += message.usage.output_tokens
    parse(text_of(message))
  rescue Anthropic::Errors::APIError => e
    Rails.logger.warn("[LocationExtractor] batch failed: #{e.class} #{e.message}")
    {}
  end

  def text_of(message)
    message.content.select { |b| b.type == :text }.map(&:text).join
  end

  # Tolerantly pull the JSON array out of the response and map it by index.
  def parse(text)
    json = text[/\[.*\]/m]
    return {} if json.blank?

    Array(JSON.parse(json)).each_with_object({}) do |row, acc|
      next unless row.is_a?(Hash) && row["i"]

      loc = Location.new(
        city:    clean(row["city"]),
        region:  clean(row["region"]),
        country: clean(row["country"])
      )
      acc[row["i"].to_i] = loc.present? ? loc : nil
    end
  rescue JSON::ParserError => e
    Rails.logger.warn("[LocationExtractor] unparseable response: #{e.message}")
    {}
  end

  def clean(value)
    s = value.to_s.strip
    return nil if s.blank? || s.casecmp?("null") || s.casecmp?("none") || s.casecmp?("n/a")

    s
  end
end
