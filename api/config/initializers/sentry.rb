# Error tracking — active only when SENTRY_DSN is configured (set it on
# Render; the free tier is plenty for this app's traffic).
if ENV["SENTRY_DSN"].present?
  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]
    config.breadcrumbs_logger = %i[active_support_logger http_logger]
    config.send_default_pii = false
    # Errors only — performance tracing off to stay within the free quota.
    config.traces_sample_rate = 0.0
  end
end
