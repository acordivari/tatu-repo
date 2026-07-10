# Sitemap for the SPA's public routes, served from the API (which owns the
# data). The SPA host's robots.txt declares this URL — the sitemap protocol
# allows a sitemap on another host when it's referenced from robots.txt.
class SitemapController < ActionController::API
  def show
    expires_in 12.hours, public: true
    render xml: sitemap_xml
  end

  private

  def sitemap_xml
    entries = [ url_entry("#{site_base}/"), url_entry("#{site_base}/shops"), url_entry("#{site_base}/map") ]
    Artist.select(:id, :handle, :updated_at).find_each do |a|
      entries << url_entry("#{site_base}/artists/#{a.handle}", lastmod: a.updated_at)
    end
    Shop.located.select(:id, :handle, :updated_at).find_each do |s|
      entries << url_entry("#{site_base}/shops/#{s.handle}", lastmod: s.updated_at)
    end

    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      #{entries.join("\n")}
      </urlset>
    XML
  end

  def url_entry(loc, lastmod: nil)
    entry = "  <url><loc>#{CGI.escapeHTML(loc)}</loc>"
    entry += "<lastmod>#{lastmod.to_date.iso8601}</lastmod>" if lastmod
    "#{entry}</url>"
  end

  # The SPA's public origin (the URLs users should land on — not this API).
  def site_base
    @site_base ||=
      ENV["SITE_BASE_URL"].presence ||
      ENV["FRONTEND_ORIGINS"].to_s.split(",").first&.strip.presence ||
      "http://localhost:5173"
  end
end
