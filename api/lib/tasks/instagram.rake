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

  desc "Enrich artists (profile -> bio/location -> geocode) via Apify. Usage: rake instagram:enrich[limit]"
  task :enrich, [:limit] => :environment do |_t, args|
    scope = Artist.where(enriched_at: nil)
    scope = scope.limit(args[:limit].to_i) if args[:limit].present?
    artists = scope.to_a
    cost = format("%.2f", artists.size / 1000.0 * 1.60)
    puts "Enriching #{artists.size} artists via Apify (est. ~$#{cost})…"
    ok = 0
    artists.each_with_index do |artist, i|
      EnrichArtistJob.perform_now(artist.id)
      ok += 1 if artist.reload.enriched_at.present?
      print "\r  #{i + 1}/#{artists.size} (located: #{Artist.located.count})"
      sleep 0.3
    end
    puts "\nEnriched #{ok} artists. #{Artist.located.count} now have map coordinates."
  end

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
