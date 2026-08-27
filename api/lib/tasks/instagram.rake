namespace :instagram do
  # Calibrated against real invoices (2026-07): apify~instagram-scraper bills per
  # dataset result, and empty/private profiles still emit a billed error item.
  # The actor page's ~$1.50/1k headline understates what we actually pay.
  APIFY_USD_PER_1K = 2.30

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
    est = format("%.2f", limit / 1000.0 * APIFY_USD_PER_1K)
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

  desc "Top up artists' own-work images toward a target count, fewest-first. " \
       "Previously attempted artists are skipped unless retry_after (days) is given. " \
       "Usage: rake instagram:backfill_work[target,limit,retry_after_days]"
  task :backfill_work, %i[target limit retry_after] => :environment do |_t, args|
    target = (args[:target].presence || 16).to_i
    retry_after = args[:retry_after].presence&.to_i&.days
    rows = artists_under(target, retry_after: retry_after)
    held = artists_held_back(target, retry_after: retry_after)
    rows = rows.first(args[:limit].to_i) if args[:limit].present?
    if rows.empty?
      abort "No artists eligible under #{target} images " \
            "(#{held} previously attempted and held back by the guard; " \
            "pass retry_after_days to include them)."
    end

    est = format("%.2f", rows.size * target / 1000.0 * APIFY_USD_PER_1K)
    puts "Backfilling #{rows.size} artists toward #{target} images each " \
         "(<= #{rows.size * target} results, est. ~$#{est})…"
    if held.positive?
      puts "Skipping #{held} previously attempted artist(s) still under target " \
           "#{retry_after ? "(attempted within #{args[:retry_after]}d)" : '(any prior attempt)'} " \
           "— re-scraping re-bills their posts for little new work."
    end

    client = ApifyClient.new
    new_posts = stored = 0
    rows.each_slice(50).with_index(1) do |batch, i|
      items = client.posts_for(batch.map { |r| r[:handle] }, per_user: target)
      # Stamp the attempt immediately — even zero-yield accounts (dead/private/
      # renamed) must leave scope, or they'd clog the head of every re-run.
      Artist.where(id: batch.map { |b| b[:id] })
            .update_all(work_fetched_at: Time.current, updated_at: Time.current)
      # Owner attribution — an artist's own posts never credit themselves — and
      # no auto-created artists from collaborative/tagged posts in the gallery.
      r = InstagramIngestor.new(items, attach_images: false, attribute_by: :owner,
                                create_missing: false).call
      new_posts += r.posts_created
      # Attach inline (throttled) so images land in the configured store (R2 in
      # prod) before the task exits, rather than via the in-process async queue.
      got = 0
      Post.needs_image.where(artist_id: batch.map { |b| b[:id] }).find_each do |post|
        AttachPostImageJob.perform_now(post.id)
        got += 1 if post.reload.image.attached?
        sleep 0.3
      end
      stored += got
      puts "  batch #{i}/#{(rows.size / 50.0).ceil}: #{items.size} results, " \
           "+#{r.posts_created} posts, +#{got} images (totals: #{new_posts} posts, #{stored} images)"
    end

    puts "\nDone. #{new_posts} new posts, #{stored} images stored. " \
         "#{artists_under(target, retry_after: retry_after).size} artists still eligible under " \
         "#{target} (limited run, or private/quiet accounts)."
    puts "Next: THREADS=8 rake storage:preprocess_variants   (pre-generate :card variants)"
  rescue ApifyClient::NotConfigured
    abort "APIFY_TOKEN is not set. Add it to api/.env."
  rescue ApifyClient::RunFailed, ApifyClient::RequestError => e
    abort "Apify run failed: #{e.message} (progress so far is saved; re-run to continue)"
  end

  desc "OCR stored post images to spot burned-in overlays (local, free). Usage: rake instagram:ocr_images[limit]"
  task :ocr_images, [:limit] => :environment do |_t, args|
    bin = ocr_binary!
    scope = Post.needs_ocr
    scope = scope.limit(args[:limit].to_i) if args[:limit].present?
    ids = scope.pluck(:id)
    abort "No stored images need OCR." if ids.empty?

    threads = ENV.fetch("THREADS", 4).to_i.clamp(1, 8)
    puts "OCR over #{ids.size} images via Apple Vision (#{threads} threads, no API cost)…"

    queue = Queue.new
    ids.each_slice(20) { |batch| queue << batch }
    done = failed = texty = 0
    lock = Mutex.new

    workers = threads.times.map do
      Thread.new do
        while (batch = queue.pop(true) rescue nil)
          Dir.mktmpdir("ocr") do |dir|
            paths = {}
            ActiveRecord::Base.connection_pool.with_connection do
              Post.with_image_blobs.where(id: batch).each do |post|
                file = File.join(dir, "#{post.id}.jpg")
                File.binwrite(file, card_bytes(post))
                paths[file] = post.id
              rescue StandardError
                lock.synchronize { failed += 1 }
              end
            end
            next if paths.empty?

            out = IO.popen([ bin, *paths.keys ], &:read)
            ActiveRecord::Base.connection_pool.with_connection do
              out.each_line do |line|
                row = JSON.parse(line) rescue next
                id = paths[row["path"]]
                next if id.nil?

                if row["error"]
                  # Vision could not decode the image: deterministic, not
                  # transient, so stamp it. Leaving it unstamped would put it
                  # back at the head of every future pass forever. A download
                  # failure earlier IS transient and is deliberately left
                  # unstamped so the next run retries it.
                  Post.where(id: id).update_all(ocr_at: Time.current, updated_at: Time.current)
                  lock.synchronize { failed += 1 }
                  next
                end
                Post.where(id: id).update_all(
                  ocr_text: row["text"].presence, ocr_text_area: row["area"],
                  ocr_lines: row["lines"], ocr_mean_height: row["mean_height"],
                  ocr_elongation: row["mean_elongation"],
                  ocr_at: Time.current, updated_at: Time.current
                )
                overlay = Post.overlay_shape?(
                  elongation: row["mean_elongation"], mean_height: row["mean_height"],
                  lines: row["lines"], text: row["text"]
                )
                lock.synchronize do
                  done += 1
                  texty += 1 if overlay
                end
              end
            end
          end
          lock.synchronize { print "\r  #{done + failed}/#{ids.size}  overlays:#{texty} failed:#{failed}" }
        end
      end
    end
    workers.each(&:join)

    puts "\nDone. #{done} scanned, #{failed} unreadable, #{texty} look like caption/UI overlays."
    puts "Review before filtering anything: rake instagram:ocr_report"
  end

  desc "Classify images as work/person/promo/other via Claude vision (COSTS MONEY). " \
       "Usage: rake instagram:classify_images[limit,scope]  scope: ambiguous (default) | notext | all"
  task :classify_images, %i[limit scope] => :environment do |_t, args|
    abort "ANTHROPIC_API_KEY is not set." unless WorkImageClassifier.configured?

    rel = Post.classifier_stale(WorkImageClassifier::VERSION).joins(:image_attachment)
    rel = case args[:scope].presence || "ambiguous"
          when "ambiguous"
            # The band OCR provably cannot resolve: tall text is a large-type
            # promo card or a lettering tattoo, and only a picture tells them apart.
            rel.where(ocr_mean_height: 0.06..)
          when "notext"  then rel.where("ocr_text IS NULL OR length(ocr_text) = 0")
          when "all"     then rel
          else abort "Unknown scope #{args[:scope].inspect} (ambiguous|notext|all)."
          end
    rel = rel.limit(args[:limit].to_i) if args[:limit].present?
    ids = rel.pluck(:id)
    abort "Nothing to classify for that scope." if ids.empty?

    est = ids.size * 0.001
    puts "Classifying #{ids.size} images with #{WorkImageClassifier::MODEL} " \
         "(~$#{format('%.2f', est)} — measured at ~$0.001/image)…"

    classifier = WorkImageClassifier.new
    threads = ENV.fetch("THREADS", 4).to_i.clamp(1, 8)
    queue = Queue.new
    ids.each { |id| queue << id }
    tally = Hash.new(0)
    done = failed = 0
    lock = Mutex.new

    workers = threads.times.map do
      Thread.new do
        while (id = queue.pop(true) rescue nil)
          ActiveRecord::Base.connection_pool.with_connection do
            post = Post.with_image_blobs.find(id)
            bytes = WorkImageClassifier.downscale(card_bytes(post))
            verdict = classifier.classify(bytes)
            if verdict.nil?
              # No verdict means unknown. Deliberately NOT stamped: leaving it
              # unclassified retries next run, where defaulting it to a kind
              # would quietly mislabel work as junk.
              lock.synchronize { failed += 1 }
            else
              post.update_columns(
                content_kind: verdict.kind, content_confidence: verdict.confidence,
                classified_at: Time.current, classifier_version: WorkImageClassifier::VERSION,
                updated_at: Time.current
              )
              lock.synchronize { done += 1; tally[verdict.kind] += 1 }
            end
          rescue StandardError => e
            lock.synchronize { failed += 1 }
            Rails.logger.warn("[classify] post #{id}: #{e.class} #{e.message}")
          end
          lock.synchronize do
            print "\r  #{done + failed}/#{ids.size}  " \
                  "#{tally.map { |k, v| "#{k}:#{v}" }.join(' ')}  failed:#{failed}  " \
                  "$#{format('%.2f', classifier.cost_usd)}"
          end
        end
      end
    end
    workers.each(&:join)

    puts "\nDone. #{done} classified, #{failed} unresolved (left for a re-run). " \
         "Cost: $#{format('%.2f', classifier.cost_usd)}."
    puts "Review before hiding anything: rake instagram:classify_report"
  end

  desc "Show what the vision classifier decided, so its verdicts can be checked before use."
  task classify_report: :environment do
    total = Post.classified.count
    abort "Nothing classified yet — run rake instagram:classify_images first." if total.zero?

    puts "Classified #{total} images.\n"
    Post.classified.group(:content_kind).count.sort_by { |_, v| -v }.each do |kind, n|
      puts format("  %-8s %6d  (%.1f%%)", kind, n, 100.0 * n / total)
    end

    puts "\nLowest-confidence verdicts — check these first:"
    Post.classified.where.not(content_confidence: nil)
        .order(:content_confidence).limit(10).each do |p|
      puts format("  %.2f  %-8s %-12s %s", p.content_confidence, p.content_kind,
                  p.ig_shortcode.to_s[0, 12], p.artist&.handle)
    end

    hidden = Post.not_work.count
    puts "\n#{hidden} images would be hidden by Post.not_work " \
         "(OCR overlays + non-work verdicts). Nothing is filtered from the site yet."
  end

  desc "Summarise what OCR found, so the overlay rule can be judged before it is used."
  task ocr_report: :environment do
    scanned = Post.ocr_done.count
    abort "Nothing has been OCR'd yet — run rake instagram:ocr_images first." if scanned.zero?

    flagged = Post.text_overlay.count
    puts "Scanned #{scanned} images. #{flagged} match the overlay rule " \
         "(elongation >= #{Post::OVERLAY_ELONGATION}, mean height < #{Post::OVERLAY_MAX_HEIGHT}, " \
         "#{Post::OVERLAY_MIN_LINES}+ lines, #{Post::OVERLAY_MIN_CHARS}+ chars).\n"

    puts "  shape of detected text        posts"
    [ [ "no text",                     Post.ocr_done.where(ocr_lines: [ nil, 0 ]) ],
      [ "tall lines (lettering?)",     Post.ocr_done.where(ocr_mean_height: 0.06..) ],
      [ "wide thin lines (overlay?)",  Post.ocr_done.where(ocr_elongation: 6.0..).where(ocr_mean_height: ...0.06) ],
      [ "other text",                  Post.ocr_done.where(ocr_lines: 1..).where(ocr_mean_height: ...0.06).where(ocr_elongation: ...6.0) ]
    ].each { |label, rel| puts format("  %-28s %6d", label, rel.count) }

    puts "\nFLAGGED as overlay — these would be hidden. Check for false positives:"
    Post.text_overlay.order(ocr_text_area: :desc).limit(10).each do |p|
      puts format("  e=%5.1f h=%.3f  %-12s %s", p.ocr_elongation, p.ocr_mean_height,
                  p.ig_shortcode.to_s[0, 12], p.ocr_text.to_s.gsub(/\s+/, " ")[0, 46])
    end

    puts "\nNOT flagged but text-heavy — confirm these really are lettering work:"
    Post.ocr_done.where(ocr_mean_height: 0.06..).where.not(ocr_text: nil)
        .order(ocr_text_area: :desc).limit(8).each do |p|
      puts format("  e=%5.1f h=%.3f  %-12s %s", p.ocr_elongation, p.ocr_mean_height,
                  p.ig_shortcode.to_s[0, 12], p.ocr_text.to_s.gsub(/\s+/, " ")[0, 46])
    end
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

  # The :card variant is what the site serves and what we OCR — 640px is ample
  # for text detection and a fraction of the original's bytes.
  def card_bytes(post)
    v = post.image.variant(:card).processed
    v.respond_to?(:download) ? v.download : v.image.blob.download
  end

  # Build the Vision OCR helper on first use. macOS-only by design: this is a
  # local pipeline step, like bin/add-artists, and never runs on the API host.
  def ocr_binary!
    require "tmpdir"
    require "json"
    bin = Rails.root.join("tmp/ocr")
    src = Rails.root.join("tools/ocr/ocr.swift")
    return bin.to_s if bin.exist? && bin.mtime > src.mtime

    abort "OCR uses Apple's Vision framework and only runs on macOS." unless RUBY_PLATFORM.include?("darwin")
    abort "swiftc not found — install the Xcode command line tools (xcode-select --install)." if `which swiftc`.strip.empty?

    puts "Building OCR helper from #{src.relative_path_from(Rails.root)}…"
    system("swiftc", "-O", src.to_s, "-o", bin.to_s) || abort("Failed to build the OCR helper.")
    bin.to_s
  end

  # Artists below the image target, fewest stored images first.
  #
  # Once attempted, an artist stays out of scope unless retry_after is passed.
  # posts_for re-bills up to `target` results per handle regardless of how many
  # we already hold, so an account still under target after an attempt (dead,
  # private, or simply short on posts) costs a full re-bill to gain at most a
  # couple of new posts. Fewest-first ordering makes this worse than it sounds:
  # the stalled accounts sort to the head of the queue and eat the budget
  # before any fresh artist is reached.
  #
  # retry_after (an ActiveSupport::Duration) lets long-idle artists back in
  # once they have plausibly posted new work.
  def artists_under(target, retry_after: nil)
    counts = Post.joins(:image_attachment).where.not(artist_id: nil).group(:artist_id).count
    # work_fetched_at alone decides. It is stamped for the whole batch straight
    # after the Apify call and before ingestion, so a run that dies mid-flight
    # has already recorded the attempt. The old fallback — treating any post
    # touched in the last day as an attempt — could not tell an owner backfill
    # from a page scrape that merely happened to include the artist's post, so
    # `instagram:scrape` locked ~536 never-backfilled artists out of the queue.
    stamped = Artist.where.not(work_fetched_at: nil)
    stamped = stamped.where(work_fetched_at: retry_after.ago..) if retry_after
    attempted = stamped.pluck(:id).to_set
    Artist.pluck(:id, :handle)
          .map { |id, handle| { id: id, handle: handle, imgs: counts[id] || 0 } }
          .select { |r| r[:imgs] < target && !attempted.include?(r[:id]) }
          .sort_by { |r| r[:imgs] }
  end

  # Count of under-target artists the attempt guard is currently excluding, so
  # a run can report what it deliberately skipped rather than silently eliding it.
  def artists_held_back(target, retry_after: nil)
    counts = Post.joins(:image_attachment).where.not(artist_id: nil).group(:artist_id).count
    scope = Artist.where.not(work_fetched_at: nil)
    scope = scope.where(work_fetched_at: retry_after.ago..) if retry_after
    scope.pluck(:id).count { |id| (counts[id] || 0) < target }
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
