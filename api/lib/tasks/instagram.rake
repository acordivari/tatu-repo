namespace :instagram do
  desc "Verify the Apify token works (no scraping cost). Usage: rake instagram:verify"
  task verify: :environment do
    token = ApifyClient.token
    abort "APIFY_TOKEN is not set. Add it to api/.env (see api/.env.example)." if token.blank?

    res = HTTParty.get("https://api.apify.com/v2/users/me", query: { token: token }, timeout: 30)
    if res.success?
      data = JSON.parse(res.body)["data"]
      puts "✅ Token OK — Apify user: #{data['username']} (plan: #{data.dig('plan', 'id') || 'free'})"
      puts "   Actor: #{ApifyClient.actor}"
    else
      abort "❌ Token rejected by Apify (HTTP #{res.code}). Double-check APIFY_TOKEN."
    end
  end

  desc "Scrape posts from @blackworkers via Apify and ingest them. Usage: rake instagram:scrape[1000] or scrape[3000,false] to skip images"
  task :scrape, [:limit, :images] => :environment do |_t, args|
    limit = (args[:limit] || 1000).to_i
    with_images = args[:images].to_s.downcase != "false"
    est = format("%.2f", limit / 1000.0 * 1.50)
    puts "Scraping up to #{limit} posts from @blackworkers via Apify (est. ~$#{est})…"
    items = ApifyClient.new.posts(username: "blackworkers", limit: limit)
    puts "Fetched #{items.size} posts. Ingesting (parsing captions for artists)…"
    # Images are a separate, observable, throttled pass (free — no Apify cost).
    report InstagramIngestor.new(items, attach_images: false).call
    if with_images
      download_images
    else
      puts "Skipped image download. Run `rake instagram:download_images` when ready."
    end
  rescue ApifyClient::NotConfigured
    abort "APIFY_TOKEN is not set. Add it to api/.env, or use rake instagram:ingest[path]."
  rescue ApifyClient::RunFailed, ApifyClient::RequestError => e
    abort "Apify run failed: #{e.message}"
  end

  desc "Download + store images for posts that don't have one yet (throttled)."
  task download_images: :environment do
    download_images
  end

  desc "Enrich artists (profiles -> bio/location) via Apify, batched. Usage: rake instagram:enrich[limit,batch]"
  task :enrich, %i[limit batch] => :environment do |_t, args|
    batch_size = (args[:batch].presence || 200).to_i
    scope = Artist.unenriched.order(posts_count: :desc)
    scope = scope.limit(args[:limit].to_i) if args[:limit].present?
    artists = scope.to_a
    abort "No un-enriched artists." if artists.empty?

    puts "Enriching #{artists.size} artists in batches of #{batch_size} via Apify…"
    totals = { fetched: 0, updated: 0, with_location: 0 }
    artists.each_slice(batch_size).with_index do |batch, i|
      r = ArtistEnricher.new(batch).call
      totals.each_key { |k| totals[k] += r[k] }
      puts "  batch #{i + 1}: fetched #{r.fetched}/#{batch.size}, " \
           "with location: #{r.with_location} (running total #{totals[:with_location]})"
    end
    puts "\nDone. Profiles fetched: #{totals[:fetched]}, with a location string: #{totals[:with_location]}."
    puts "Next: rake instagram:extract_locations   (bio -> evidence ledger -> coordinates)"
  rescue ApifyClient::NotConfigured
    abort "APIFY_TOKEN is not set. Add it to api/.env."
  rescue ApifyClient::RunFailed, ApifyClient::RequestError => e
    abort "Apify run failed: #{e.message}"
  end

  desc "Extract structured locations from artist bios via Claude. Usage: rake instagram:extract_locations[limit]"
  task :extract_locations, [:limit] => :environment do |_t, args|
    abort "ANTHROPIC_API_KEY is not set. Add it to api/.env (see api/.env.example)." unless LocationExtractor.configured?

    scope = Artist.needs_location_extraction.order(posts_count: :desc)
    scope = scope.limit(args[:limit].to_i) if args[:limit].present?
    artists = scope.to_a
    abort "No artists need location extraction." if artists.empty?

    extractor = LocationExtractor.new
    puts "Extracting location + shop for #{artists.size} artists via Claude (#{LocationExtractor::MODEL})…"
    with_loc = 0
    with_shop = 0
    artists.each_slice(100) do |chunk|
      results = extractor.extract(chunk.map(&:bio))
      chunk.each_with_index do |artist, i|
        ext = results[i]
        if ext
          ArtistSignalBuilder.new(artist, ext).call
          with_loc += 1 if ext.location?
          with_shop += 1 if ext.shop?
        end
        artist.update_columns(location_extracted_at: Time.current, updated_at: Time.current)
      end
      print "\r  processed up to #{[artists.index(chunk.last) + 1, artists.size].min}/#{artists.size} | location:#{with_loc} shop:#{with_shop} | cost: $#{extractor.cost_usd.round(3)}"
    end
    puts "\nDone. #{with_loc} location signals, #{with_shop} shop links, #{Shop.count} unique shops. Cost: $#{extractor.cost_usd.round(3)}."
    puts "Next: rake instagram:resolve_locations   (resolve best signal -> map coordinates)"
  end

  desc "Resolve each artist's location from the evidence ledger (throttled geocoding). Usage: rake instagram:resolve_locations[limit]"
  task :resolve_locations, [:limit] => :environment do |_t, args|
    scope = Artist.where(id: LocationSignal.select(:artist_id).distinct)
    scope = scope.limit(args[:limit].to_i) if args[:limit].present?
    artists = scope.to_a
    abort "No artists have location signals yet." if artists.empty?

    puts "Resolving locations for #{artists.size} artists…"
    tally = Hash.new(0)
    artists.each_with_index do |artist, i|
      status = LocationResolver.new(artist).call.status
      tally[status] += 1
      # Only the :located path made a (throttled) geocoding call.
      sleep 1.1 if status == :located
      print "\r  #{i + 1}/#{artists.size} | located:#{tally[:located]} unchanged:#{tally[:unchanged]} unlocatable:#{tally[:unlocatable]}"
    end
    puts "\nDone. On map now: #{Artist.located.count}."
  end

  desc "Canonicalize artists' region strings (dedupe CA/California, Québec/Quebec, Москва/Moscow) via Claude. Usage: rake instagram:canonicalize_regions[force]"
  task :canonicalize_regions, [:force] => :environment do |_t, args|
    abort "ANTHROPIC_API_KEY is not set." unless RegionCanonicalizer.configured?

    scope = Artist.where.not(region: [nil, ""])
    scope = scope.where(region_canonical: [nil, ""]) unless args[:force] == "force"
    # Distinct (country, region) pairs — we pay Claude once per pair, then fan
    # the result out to every artist sharing it.
    pairs = scope.distinct.pluck(:country, :region)
    abort "No regions need canonicalization. (Pass [force] to redo all.)" if pairs.empty?

    puts "Canonicalizing #{pairs.size} distinct (country, region) pairs via Claude (#{RegionCanonicalizer::MODEL})…"
    canon = RegionCanonicalizer.new
    mapping = canon.canonicalize(pairs)

    updated = 0
    changed = 0
    mapping.each do |(country, region), label|
      rel = Artist.where(region: region)
      rel = country.nil? ? rel.where(country: nil) : rel.where(country: country)
      n = rel.update_all(region_canonical: label, updated_at: Time.current)
      updated += n
      changed += n if label.to_s.casecmp(region.to_s) != 0
    end
    puts "\nDone. #{pairs.size} pairs -> canonical labels; #{updated} artists updated " \
         "(#{changed} got a different label). Distinct regions now: " \
         "#{Artist.where.not(region_canonical: [nil, '']).distinct.count(:region_canonical)}. " \
         "Cost: $#{canon.cost_usd.round(4)}."
  end

  desc "Resolve shops to verified Google Places businesses, then emit location signals. Usage: rake instagram:resolve_shops[limit]"
  task :resolve_shops, [:limit] => :environment do |_t, args|
    abort "GOOGLE_MAPS_API_KEY is not set. Add it to api/.env (see api/.env.example)." unless GooglePlacesResolver.configured?

    # Most-shared shops first (resolving them helps the most artists).
    scope = Shop.unresolved.joins(:memberships).group("shops.id").order(Arel.sql("COUNT(memberships.id) DESC"))
    scope = scope.limit(args[:limit].to_i) if args[:limit].present?
    shops = scope.to_a
    abort "No unresolved shops." if shops.empty?

    resolver = GooglePlacesResolver.new
    puts "Resolving #{shops.size} shops via Google Places (Text Search; within free tier)…"
    matched = 0
    rejected = 0
    shops.each_with_index do |shop, i|
      member = located_member(shop)
      place = resolver.lookup(shop_query(shop, member))
      if place && ShopPlaceVerifier.new(shop, place, member).accept?
        shop.update!(
          name: place.name, google_place_id: place.place_id, business_status: place.business_status,
          address_raw: place.formatted_address, city: place.city, region: place.region,
          country: place.country, latitude: place.latitude, longitude: place.longitude,
          profile_scraped_at: Time.current
        )
        emit_shop_signals(shop)
        matched += 1
      else
        # Mark attempted (no re-bill) but DON'T trust an unverified/false match.
        rejected += 1 if place
        shop.update_columns(profile_scraped_at: Time.current, updated_at: Time.current)
      end
      print "\r  #{i + 1}/#{shops.size} matched:#{matched} rejected:#{rejected}"
      sleep 0.1
    end
    puts "\nMatched #{matched}/#{shops.size} shops (#{rejected} matches rejected as false/unverifiable)."
    puts "Next: rake instagram:resolve_locations   (upgrade artists to their shop's verified location)"
  end

  def located_member(shop)
    shop.memberships.joins(:artist).merge(Artist.located).first&.artist
  end

  # Build a Google query: shop handle/name + a city hint from a located member
  # so we match the right business, not a same-named shop elsewhere.
  def shop_query(shop, member = nil)
    hint = member && [member.city, member.region, member.country].compact_blank.first(2).join(", ")
    [shop.name.presence || shop.handle.tr("._", " "), "tattoo", hint].compact_blank.join(" ")
  end

  # One shop_google_places signal per member artist, carrying the shop's location.
  def emit_shop_signals(shop)
    shop.memberships.includes(:artist).find_each do |m|
      sig = m.artist.location_signals.find_or_initialize_by(source_type: "shop_google_places", shop_id: shop.id)
      sig.assign_attributes(city: shop.city, region: shop.region, country: shop.country,
                            source_account: "google_places", observed_at: Time.current,
                            raw: shop.address_raw.to_s[0, 255])
      sig.save!
    end
  end

  # NOTE: the legacy `instagram:geocode` task was removed — geocoding now happens
  # through the evidence ledger via `instagram:resolve_locations` (which calls
  # LocationResolver, the single source of truth for artist coordinates).

  desc "Ingest scraped posts from a local JSON file (Apify dataset export). Usage: rake instagram:ingest[path/to.json]"
  task :ingest, [:path] => :environment do |_t, args|
    path = args[:path] or abort "Provide a JSON path: rake instagram:ingest[posts.json]"
    items = JSON.parse(File.read(path))
    puts "Ingesting #{items.size} posts from #{path}…"
    report InstagramIngestor.new(items).call
  end

  desc "Bootstrap from the legacy Rails app's seed hashes (image/link/handle, no captions)."
  task import_legacy: :environment do
    legacy = Rails.root.join("../legacy/db/seeds.rb")
    abort "Legacy seeds not found at #{legacy}" unless File.exist?(legacy)

    # Each legacy record is one line: {image: "…", link: "…", Instagram: "@handle"}
    items = File.read(legacy).scan(
      /image:\s*"([^"]*)".*?link:\s*"([^"]*)".*?Instagram:\s*"([^"]*)"/
    ).map do |image, link, handle|
      # Synthesize a caption so the normal attribution path applies.
      { "url" => link, "displayUrl" => image, "caption" => "Tattoo by #{handle}" }
    end
    puts "Importing #{items.size} legacy posts…"
    # Skip image downloads: the legacy CDN URLs have long since expired.
    report InstagramIngestor.new(items, attach_images: false).call
  end

  def report(result)
    puts <<~OUT
      Done.
        posts created:    #{result.posts_created}
        posts updated:    #{result.posts_updated}
        artists created:  #{result.artists_created}
        unattributed:     #{result.unattributed}
    OUT
  end

  # Download + store images inline so a backfill is observable and complete.
  # Throttled to stay non-disruptive to Instagram's CDN.
  def download_images
    pending = Post.needs_image.to_a
    return puts("All posts already have stored images.") if pending.empty?

    puts "Downloading #{pending.size} images (throttled)…"
    ok = 0
    pending.each_with_index do |post, i|
      AttachPostImageJob.perform_now(post.id)
      ok += 1 if post.reload.image.attached?
      print "\r  #{i + 1}/#{pending.size} stored:#{ok}"
      sleep 0.4
    end
    puts "\nStored #{ok}/#{pending.size} images (#{pending.size - ok} unavailable/expired)."
  end
end
