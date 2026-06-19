# Be sure to restart your server when you modify this file.
#
# Allow the React SPA (Vite dev server / deployed frontend) to call the API.
# Origins are configurable via FRONTEND_ORIGINS (comma-separated).

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(
      ENV.fetch("FRONTEND_ORIGINS", "http://localhost:5173,http://127.0.0.1:5173")
         .split(",")
         .map(&:strip)
    )

    resource "*",
             headers: :any,
             methods: %i[get post put patch delete options head],
             expose: %w[X-Page X-Total-Count X-Total-Pages]
  end
end
