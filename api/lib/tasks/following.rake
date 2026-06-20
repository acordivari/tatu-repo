# Pipeline for discovering artists from a personal Instagram follow list.
#   import      -> queue unknown handles, tag known artists with the new source
#   classify    -> scrape candidate profiles, LLM-classify, auto-approve/route
#   review      -> list borderline candidates awaiting a human
#   approve/reject -> act on a reviewed candidate
#   fetch_work  -> scrape sample posts so new artists have thumbnails
namespace :following do
  AUTO_APPROVE_CONFIDENCE = 0.8

  desc "Import an Instagram following.json export. Usage: rake following:import[path/to/following.json]"
  task :import, [:path] => :environment do |_t, args|
    path = args[:path] or abort "Provide the export path: rake following:import[following.json]"
    abort "File not found: #{path}" unless File.exist?(path)

    r = FollowingImporter.new(path).call
    puts <<~OUT
      Imported #{r.total} followed handles.
        already-known artists (tagged 'personal_following'): #{r.corroborated}
        new candidates queued for classification:            #{r.queued}
        already queued (skipped):                            #{r.skipped}
      Next: rake following:classify
    OUT
  end

  desc "Scrape + classify pending candidates as tattoo artists. Usage: rake following:classify[limit]"
  task :classify, [:limit] => :environment do |_t, args|
    abort "ANTHROPIC_API_KEY is not set." unless LocationExtractor.configured?

    scope = ArtistCandidate.pending
    scope = scope.limit(args[:limit].to_i) if args[:limit].present?
    candidates = scope.to_a
    abort "No pending candidates." if candidates.empty?

    classifier = ArtistClassifier.new
    tally = Hash.new(0)
    puts "Classifying #{candidates.size} candidates (scrape + Claude)…"
    candidates.each_slice(50) do |batch|
      scrape_profiles(batch)            # fill bio/category/etc. from Apify
      verdicts = classifier.classify(batch)
      batch.each_with_index do |c, i|
        outcome = apply_verdict(c, verdicts[i])
        tally[outcome] += 1
      end
      print "\r  approved:#{tally[:approved]} review:#{tally[:review]} rejected:#{tally[:rejected]} | classify cost: $#{classifier.cost_usd.round(3)}"
    end
    puts "\nDone. Approved #{tally[:approved]} new artists, #{tally[:review]} need review, #{tally[:rejected]} rejected."
    puts "Review the borderline ones: rake following:review"
  end

  desc "List candidates awaiting human review."
  task review: :environment do
    rows = ArtistCandidate.review.order(confidence: :desc)
    abort "Nothing awaiting review." if rows.empty?
    puts "#{rows.size} candidates to review (approve: rake following:approve[handle] / reject: following:reject[handle]):"
    rows.each do |c|
      puts sprintf("  @%-22s conf:%.2f cat:%-20s | %s", c.handle, c.confidence || 0, c.category.to_s[0,20], c.bio.to_s.gsub(/\s+/," ")[0,60])
    end
  end

  desc "Approve a reviewed candidate. Usage: rake following:approve[handle]"
  task :approve, [:handle] => :environment do |_t, args|
    c = ArtistCandidate.find_by(handle: Artist.normalize_handle(args[:handle])) or abort "No candidate @#{args[:handle]}"
    artist = c.approve!
    puts "Approved @#{artist.handle} (sources: #{artist.sources.join(', ')}). Run enrich/extract/resolve to locate."
  end

  desc "Reject a reviewed candidate. Usage: rake following:reject[handle]"
  task :reject, [:handle] => :environment do |_t, args|
    c = ArtistCandidate.find_by(handle: Artist.normalize_handle(args[:handle])) or abort "No candidate @#{args[:handle]}"
    c.update!(status: "rejected")
    puts "Rejected @#{c.handle}."
  end

  desc "Scrape sample posts for artists that have none yet (thumbnails). Usage: rake following:fetch_work[limit]"
  task :fetch_work, [:limit] => :environment do |_t, args|
    scope = Artist.where("'personal_following' = ANY(sources)").where.missing(:posts)
    scope = scope.limit(args[:limit].to_i) if args[:limit].present?
    artists = scope.to_a
    abort "No follow-sourced artists need work images." if artists.empty?

    puts "Fetching ~6 posts each for #{artists.size} artists…"
    ingested = 0
    artists.each_slice(20) do |batch|
      items = ApifyClient.new.posts_for(batch.map(&:handle), per_user: 6)
      # Attribute by the account scraped (their own work), NOT by caption —
      # an artist's own posts don't credit themselves.
      r = InstagramIngestor.new(items, attach_images: true, attribute_by: :owner,
                                source_account: "personal_following", create_missing: false).call
      ingested += r.posts_created
      print "\r  posts ingested: #{ingested}"
    end
    puts "\nDone. Run rake instagram:download_images if any images are still pending."
  end

  # --- helpers ---

  def scrape_profiles(candidates)
    profiles = ApifyClient.new.profiles(candidates.map(&:handle)).index_by { |p| p[:handle] }
    candidates.each do |c|
      p = profiles[c.handle] || {}
      c.update!(
        full_name: p[:full_name], bio: p[:biography], category: p[:category],
        followers_count: p[:followers_count], posts_count: p[:posts_count],
        scraped_at: Time.current
      )
    end
  rescue ApifyClient::NotConfigured
    abort "APIFY_TOKEN is not set."
  end

  def apply_verdict(candidate, verdict)
    if verdict.nil?
      candidate.update!(status: "review", classified_at: Time.current)
      return :review
    end
    candidate.update!(classification: verdict.verdict, confidence: verdict.confidence,
                      reason: verdict.reason, classified_at: Time.current)
    case verdict.verdict
    when "tattoo_artist"
      if verdict.confidence >= AUTO_APPROVE_CONFIDENCE
        candidate.approve!
        :approved
      else
        candidate.update!(status: "review"); :review
      end
    when "maybe"
      candidate.update!(status: "review"); :review
    else
      candidate.update!(status: "rejected"); :rejected
    end
  end
end
