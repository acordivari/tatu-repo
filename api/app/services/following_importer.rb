# Parses an Instagram "Download Your Information" following export and queues
# handles for classification. Known artists (already in the directory) are just
# tagged with the new source — no need to re-classify them. Only unknown handles
# become candidates.
#
# Accepts the JSON export format:
#   { "relationships_following": [ { "string_list_data": [ { "value": "handle" } ] } ] }
# and degrades to a plain array of handles or a list of IG URLs.
class FollowingImporter
  SOURCE = "personal_following".freeze

  Result = Struct.new(:total, :corroborated, :queued, :skipped, keyword_init: true)

  def initialize(path)
    @path = path
  end

  def call
    handles = extract_handles
    result = Result.new(total: handles.size, corroborated: 0, queued: 0, skipped: 0)

    handles.each do |handle|
      if (artist = Artist.find_by(handle: handle))
        artist.update_columns(sources: (Array(artist.sources) | [SOURCE]), updated_at: Time.current)
        result.corroborated += 1
      elsif ArtistCandidate.exists?(handle: handle)
        result.skipped += 1
      else
        ArtistCandidate.create!(handle: handle, source: SOURCE, status: "pending")
        result.queued += 1
      end
    end
    result
  end

  private

  def extract_handles
    data = JSON.parse(File.read(@path))
    raw =
      case data
      when Array then data.flat_map { |e| handle_from(e) }
      when Hash  then Array(data["relationships_following"] || data["following"]).flat_map { |e| handle_from(e) }
      else []
      end
    raw.map { |h| Artist.normalize_handle(h) }.compact.uniq
  rescue JSON::ParserError => e
    raise "Could not parse #{@path}: #{e.message}"
  end

  # Pull a handle out of the various shapes a following entry can take.
  # The IG export puts the handle in "title"; hrefs use a /_u/ redirect prefix
  # (https://www.instagram.com/_u/HANDLE), so account for that when falling back.
  def handle_from(entry)
    case entry
    when String
      [from_url(entry) || entry]
    when Hash
      return [entry["title"]] if entry["title"].present?

      list = entry["string_list_data"]
      if list.is_a?(Array)
        list.map { |s| s["value"].presence || from_url(s["href"]) }
      else
        [entry["value"] || entry["username"] || entry["handle"]]
      end
    else []
    end.compact
  end

  def from_url(url)
    url.to_s[%r{instagram\.com/(?:_u/)?([^/?]+)}, 1]
  end
end
