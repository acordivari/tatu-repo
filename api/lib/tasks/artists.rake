# Add artists ad-hoc — one-offs or small batches — and run the full enrichment
# pipeline on just them: profile (Apify) -> bio location + shop into the evidence
# ledger (Claude) -> geocode -> a sample of their own work for thumbnails.
#
# Idempotent (find_or_create by handle, skips work already done) and runs against
# whatever database + Active Storage service the environment points at, so it
# works the same in the Render shell (writes straight to prod + R2) or locally.
namespace :artists do
  desc "Add artist(s) by handle and enrich. Usage: rake 'artists:add[handle1,handle2,...]'"
  task :add, [:handle] => :environment do |_t, args|
    handles = [args[:handle], *args.extras].compact
                                           .map { |h| Artist.normalize_handle(h) }.compact.uniq
    abort "Usage: rake 'artists:add[handle1,handle2,...]'" if handles.empty?

    artists = handles.map { |h| Artist.find_or_create_by!(handle: h) }
    artists.each { |a| a.update_columns(sources: (Array(a.sources) | ["manual"]), updated_at: Time.current) }
    puts "Adding #{artists.size}: #{artists.map { |a| "@#{a.handle}" }.join(', ')}"

    # 1) Profile: name, bio, website, location string (Apify).
    if ApifyClient.token.present?
      puts "→ profiles…"
      ArtistEnricher.new(artists).call
      artists.each(&:reload)
    else
      puts "→ skip profiles (APIFY_TOKEN not set)"
    end

    # 2) Bio -> location + shop signals in the evidence ledger (Claude).
    if LocationExtractor.configured?
      puts "→ locations…"
      results = LocationExtractor.new.extract(artists.map(&:bio))
      artists.each_with_index do |a, i|
        ArtistSignalBuilder.new(a, results[i]).call if results[i]
        a.update_columns(location_extracted_at: Time.current, updated_at: Time.current)
      end
    else
      puts "→ skip locations (ANTHROPIC_API_KEY not set)"
    end

    # 3) Resolve each artist from its best signal -> coordinates (throttled).
    puts "→ geocoding…"
    artists.each { |a| LocationResolver.new(a).call; sleep 1.1 }

    # 4) A few of their own posts for thumbnails (owner-attributed). Images are
    #    attached synchronously so they land in the configured store (R2 in prod)
    #    before the task exits, rather than via the async queue.
    if ApifyClient.token.present?
      puts "→ sample work + images…"
      items = ApifyClient.new.posts_for(artists.map(&:handle), per_user: 6)
      InstagramIngestor.new(items, attach_images: false, attribute_by: :owner,
                            source_account: "manual", create_missing: false).call
      Post.where(artist: artists).needs_image.find_each do |post|
        AttachPostImageJob.perform_now(post.id)
        sleep 0.3
      end
    end

    puts "\nDone:"
    artists.each(&:reload).each do |a|
      loc = [a.city, a.region, a.country].compact_blank.join(", ").presence || "no location"
      posts = a.posts.to_a
      with_img = posts.count { |p| p.image.attached? }
      puts "  @#{a.handle} — #{a.name.to_s.inspect} — #{loc} — #{posts.size} posts (#{with_img} with image)"
    end
    puts "\nNamed a studio? Run `rake instagram:resolve_shops` to upgrade it to a " \
         "verified Google location (conf 0.97)."
  end

  # Taking an artist off the site keeps the row (and its posts) as a tombstone:
  # deleting it would let the next @blackworkers scrape or follow-list import
  # re-create the artist from a caption credit, quietly re-publishing them.
  desc "Take an artist off the public site by hand. Usage: rake 'artists:delist[handle,reason]'"
  task :delist, %i[handle reason] => :environment do |_t, args|
    reason = args[:reason].presence or abort "Give a reason, e.g. rake 'artists:delist[handle,deceased]'"
    artist = Artist.find_by(handle: Artist.normalize_handle(args[:handle])) or abort "No artist @#{args[:handle]}."
    artist.update_columns(delisted_at: Time.current, delisted_reason: reason, updated_at: Time.current)
    puts "Delisted @#{artist.handle} (#{reason}). Hidden from the directory, search, map, " \
         "shop rosters, posts feed and sitemap; its page now 404s. Undo: rake 'artists:relist[#{artist.handle}]'"
  end

  desc "Put a delisted artist back on the public site. Usage: rake 'artists:relist[handle]'"
  task :relist, [ :handle ] => :environment do |_t, args|
    artist = Artist.find_by(handle: Artist.normalize_handle(args[:handle])) or abort "No artist @#{args[:handle]}."
    artist.update_columns(delisted_at: nil, delisted_reason: nil, updated_at: Time.current)
    puts "Relisted @#{artist.handle}#{artist.profile_missing_at ? ' (still hidden: Instagram profile marked missing)' : ''}."
  end
end
