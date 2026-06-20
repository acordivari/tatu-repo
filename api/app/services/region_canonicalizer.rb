# Canonicalizes freeform region/state strings to ONE consistent English/Latin
# label per real-world region, so the directory's region facet and filter
# dedupe reliably. The scraped `region` column is a mess of equivalent variants
# — "California"/"CA", "Québec"/"Quebec", "Москва" (Cyrillic) — which split the
# facet counts and make exact-match filtering miss rows.
#
# Country context disambiguates (a "Victoria" in Australia is not the one in
# Canada), so input is (country, region) pairs, not bare region strings. Claude
# Haiku does the normalization across scripts/abbreviations/accents that a hand
# map can't cover for 200+ international values.
#
# Returns a Hash keyed by [country, region] => canonical label. Deterministic
# inputs (same pairs) cost the same; callers should dedupe to DISTINCT pairs
# before calling so we never pay to canonicalize the same pair twice.
class RegionCanonicalizer
  class NotConfigured < StandardError; end

  MODEL = :"claude-haiku-4-5"
  BATCH_SIZE = 60

  PRICE_IN = 1.0
  PRICE_OUT = 5.0

  INSTRUCTIONS = <<~TXT.freeze
    You normalize the "state/region/province" field of tattoo-artist locations to
    a single canonical label so duplicates collapse. You are given numbered
    (country, region) pairs. For each, return the canonical region name.
    Return ONLY a JSON array — one object per input, in order, with keys:
      "i": the input's index number
      "canonical": the canonical region label
    Rules:
    - Canonical labels are in ENGLISH using the LATIN alphabet
      ("Москва" -> "Moscow", "Catalunya" -> "Catalonia", "Île-de-France" -> "Ile-de-France",
       "Baviera" -> "Bavaria").
    - Expand obvious abbreviations to the full region name using the country as
      context ("CA" in United States -> "California"; "AB" in Canada -> "Alberta";
      "SP" in Brazil -> "São Paulo" but written Latin/ASCII -> "Sao Paulo").
    - Fold accents to plain ASCII ("Québec" -> "Quebec", "São Paulo" -> "Sao Paulo").
    - Use the standard top-level region (state/province/region) for the place. If
      the input is actually a city, map it to its state/region/province
      ("Brooklyn", United States -> "New York").
    - If you cannot confidently canonicalize, echo the input region back, trimmed.
    - Output the JSON array and nothing else.
  TXT

  attr_reader :input_tokens, :output_tokens

  def initialize(api_key: self.class.api_key)
    raise NotConfigured, "ANTHROPIC_API_KEY is not set" if api_key.blank?

    require "anthropic"
    @client = Anthropic::Client.new(api_key: api_key)
    @input_tokens = 0
    @output_tokens = 0
  end

  def self.api_key
    ENV["ANTHROPIC_API_KEY"].presence || Rails.application.credentials.dig(:anthropic, :api_key)
  end

  def self.configured?
    api_key.present?
  end

  def cost_usd
    (input_tokens / 1_000_000.0 * PRICE_IN) + (output_tokens / 1_000_000.0 * PRICE_OUT)
  end

  # pairs: array of [country, region]. Returns { [country, region] => "Canonical" }.
  def canonicalize(pairs)
    pairs = pairs.uniq
    result = {}
    pairs.each_slice(BATCH_SIZE) do |slice|
      canonicalize_batch(slice).each { |i, label| result[slice[i]] = label if i.between?(0, slice.size - 1) }
    end
    result
  end

  private

  def canonicalize_batch(pairs)
    prompt = INSTRUCTIONS + "\n\nPairs:\n" +
             pairs.each_with_index.map { |(country, region), i| "#{i}: country=#{country} | region=#{region}" }.join("\n")

    message = @client.messages.create(
      model: MODEL,
      max_tokens: 4096,
      messages: [{ role: "user", content: prompt }]
    )
    @input_tokens += message.usage.input_tokens
    @output_tokens += message.usage.output_tokens
    parse(text_of(message), pairs)
  rescue Anthropic::Errors::APIError => e
    Rails.logger.warn("[RegionCanonicalizer] batch failed: #{e.class} #{e.message}")
    {}
  end

  def text_of(message)
    message.content.select { |b| b.type == :text }.map(&:text).join
  end

  # Map JSON rows back to slice indices; fall back to the raw region on any gap
  # so a flaky response degrades to "unchanged" rather than dropping the row.
  def parse(text, pairs)
    json = text[/\[.*\]/m]
    out = {}
    if json.present?
      Array(JSON.parse(json)).each do |row|
        next unless row.is_a?(Hash) && row["i"]

        i = row["i"].to_i
        label = row["canonical"].to_s.strip
        out[i] = label if i.between?(0, pairs.size - 1) && label.present?
      end
    end
    # Backfill any missing index with the trimmed raw region.
    pairs.each_with_index { |(_c, region), i| out[i] ||= region.to_s.strip }
    out
  rescue JSON::ParserError => e
    Rails.logger.warn("[RegionCanonicalizer] unparseable response: #{e.message}")
    pairs.each_with_index.to_h { |(_c, region), i| [i, region.to_s.strip] }
  end
end
