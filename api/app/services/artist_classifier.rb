# Classifies whether a scraped Instagram profile is a working tattoo artist,
# using Claude Haiku over bio + IG category + name. Returns a verdict and a
# confidence so the caller can auto-approve the confident ones and route the
# borderline ones to human review.
class ArtistClassifier
  class NotConfigured < StandardError; end

  MODEL = :"claude-haiku-4-5"
  BATCH_SIZE = 25
  PRICE_IN = 1.0
  PRICE_OUT = 5.0

  Verdict = Struct.new(:verdict, :confidence, :reason, keyword_init: true)

  INSTRUCTIONS = <<~TXT.freeze
    Decide whether each Instagram account is an individual WORKING TATTOO ARTIST
    (a person who tattoos), based on their name, bio, and Instagram category.
    Return ONLY a JSON array — one object per account, in input order, keys:
      "i": index number
      "verdict": "tattoo_artist" | "maybe" | "not_artist"
      "confidence": 0.0–1.0 (how sure you are of the verdict)
    Guidance:
    - tattoo_artist: clearly tattoos people (bio/category says tattooer/tattoo artist,
      mentions booking/appointments for tattoos, blackwork/fineline/etc., shows a studio).
    - not_artist: clearly NOT an individual tattooer — friends/personal accounts, tattoo
      SUPPLY/equipment brands (needles, ink, machines), apparel brands, photographers,
      piercers-only, meme/repost pages, musicians, a studio's own account (a shop, not a person).
    - maybe: genuinely ambiguous (sparse bio, could be an artist or a fan/apprentice).
    - IG category "Tattoo & Piercing Shop" + an individual name leans tattoo_artist;
      the same category for an account clearly representing a studio leans not_artist.
    Output the JSON array and nothing else.
  TXT

  def initialize(api_key: LocationExtractor.api_key)
    raise NotConfigured, "ANTHROPIC_API_KEY is not set" if api_key.blank?

    require "anthropic"
    @client = Anthropic::Client.new(api_key: api_key)
    @input_tokens = 0
    @output_tokens = 0
  end

  def cost_usd
    (@input_tokens / 1_000_000.0 * PRICE_IN) + (@output_tokens / 1_000_000.0 * PRICE_OUT)
  end

  # candidates: ArtistCandidate records (with scraped bio/category/name).
  # Returns array of Verdict aligned to input.
  def classify(candidates)
    results = Array.new(candidates.size)
    candidates.each_slice(BATCH_SIZE).with_index do |slice, si|
      offset = si * BATCH_SIZE
      classify_batch(slice).each { |i, v| results[offset + i] = v if i.between?(0, slice.size - 1) }
    end
    results
  end

  private

  def classify_batch(candidates)
    prompt = INSTRUCTIONS + "\n\nAccounts:\n" + candidates.each_with_index.map { |c, i|
      "#{i}: handle=@#{c.handle} | name=#{c.full_name} | category=#{c.category} | " \
      "posts=#{c.posts_count} | bio=#{c.bio.to_s.gsub(/\s+/, ' ').strip[0, 200]}"
    }.join("\n")

    message = @client.messages.create(model: MODEL, max_tokens: 3000, messages: [{ role: "user", content: prompt }])
    @input_tokens += message.usage.input_tokens
    @output_tokens += message.usage.output_tokens
    parse(message.content.select { |b| b.type == :text }.map(&:text).join)
  rescue Anthropic::Errors::APIError => e
    Rails.logger.warn("[ArtistClassifier] batch failed: #{e.class} #{e.message}")
    {}
  end

  def parse(text)
    json = text[/\[.*\]/m]
    return {} if json.blank?

    Array(JSON.parse(json)).each_with_object({}) do |row, acc|
      next unless row.is_a?(Hash) && row["i"] && ArtistCandidate::CLASSIFICATIONS.include?(row["verdict"])

      acc[row["i"].to_i] = Verdict.new(
        verdict: row["verdict"], confidence: row["confidence"].to_f, reason: row["reason"]
      )
    end
  rescue JSON::ParserError
    {}
  end
end
