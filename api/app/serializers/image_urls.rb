# Builds public-facing URLs for stored images WITHOUT routing every <img>
# request through this app (the old rails_blob_url redirect made each
# thumbnail a Rails request). Preference order:
#
#   1. R2_PUBLIC_BASE — the bucket's public host (r2.dev subdomain or a custom
#      domain). URLs are permanent and CDN/browser-cacheable. Set it once the
#      bucket has public access enabled.
#   2. The storage service's own URL (signed, straight to R2 in production,
#      Disk in dev). Expiry is extended to 1 week in production.rb so URLs
#      embedded in cached JSON stay valid.
module ImageUrls
  module_function

  # Grid-tile URL for a post image: the :card variant when it can be produced,
  # the stored original otherwise, the (expiring) Instagram source URL only if
  # the download never completed.
  def post_image_url(post)
    return post.image_url unless post.image.attached?

    blob_url(post.image.variant(:card).processed.image.blob)
  rescue StandardError => e
    # A single unprocessable file (corrupt download, missing object) must not
    # take down a whole directory page — serve that post's original instead.
    Rails.logger.warn("ImageUrls: variant failed for post=#{post.id}: #{e.class} #{e.message}")
    blob_url(post.image.blob)
  end

  def blob_url(blob)
    if (base = ENV["R2_PUBLIC_BASE"].presence)
      "#{base.chomp("/")}/#{blob.key}"
    else
      # Reuse each signed URL for days rather than re-signing per request —
      # browsers cache images by exact URL, so churning signatures would
      # defeat their cache. 3-day reuse still leaves ≥4 days of validity
      # on the 1-week signature.
      Rails.cache.fetch("image-url/#{blob.key}", expires_in: 3.days) { blob.url }
    end
  end
end
