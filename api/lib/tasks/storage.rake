namespace :storage do
  # One-time migration of every Active Storage blob from the local Disk service
  # to Cloudflare R2 (the production object store). Run it LOCALLY, where the
  # files physically live, with the R2_* env vars set:
  #
  #   R2_ACCESS_KEY_ID=… R2_SECRET_ACCESS_KEY=… R2_ENDPOINT=… R2_BUCKET=… \
  #     RBENV_VERSION=3.3.0 bin/rails storage:migrate_to_r2
  #
  # Idempotent: blobs already present in R2 are skipped, so it's safe to re-run.
  desc "Copy all Active Storage blobs from the local disk to Cloudflare R2"
  task migrate_to_r2: :environment do
    source = ActiveStorage::Blob.services.fetch(:local)
    dest   = ActiveStorage::Blob.services.fetch(:cloudflare)

    total = ActiveStorage::Blob.count
    copied = skipped = missing = 0

    ActiveStorage::Blob.find_each.with_index do |blob, i|
      if dest.exist?(blob.key)
        skipped += 1
      elsif source.exist?(blob.key)
        source.open(blob.key, checksum: blob.checksum) do |file|
          dest.upload(blob.key, file, checksum: blob.checksum, content_type: blob.content_type)
        end
        copied += 1
      else
        missing += 1 # blob row with no file on disk (nothing to copy)
      end
      print "\r  #{i + 1}/#{total}  copied:#{copied} skipped:#{skipped} missing:#{missing}" if (i % 25).zero?
    end

    puts "\nDone. copied:#{copied} skipped:#{skipped} missing:#{missing} of #{total} blobs."
    puts "Missing files are blob rows whose disk file is gone — safe to ignore." if missing.positive?
  end

  # Serializers serve the :card variant of every post image (see ImageUrls);
  # this generates them all up front so no request ever pays the resize cost.
  # Run it like bin/add-artists — locally, against production:
  #
  #   DATABASE_URL=$PROD_DATABASE_URL R2_ACCESS_KEY_ID=… R2_SECRET_ACCESS_KEY=… \
  #     R2_ENDPOINT=… R2_BUCKET=… RAILS_ENV=production RBENV_VERSION=3.3.0 \
  #     bin/rails storage:preprocess_variants
  #
  # Idempotent: already-processed variants are skipped by Active Storage.
  desc "Pre-generate the :card variant for every stored post image"
  task preprocess_variants: :environment do
    scope = Post.joins(:image_attachment)
    total = scope.count
    done = failed = 0

    scope.with_image_blobs.find_each do |post|
      post.image.variant(:card).processed
      done += 1
    rescue StandardError => e
      failed += 1
      puts "\n  ! post #{post.id} (#{post.ig_shortcode}): #{e.class}: #{e.message}"
    ensure
      print "\r  #{done + failed}/#{total}  ok:#{done} failed:#{failed}"
    end

    puts "\nDone. Failed posts fall back to serving their original image."
  end
end
