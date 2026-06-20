Rails.application.routes.draw do
  # Health check for load balancers / uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :artists, only: %i[index show] do
        collection do
          # Lightweight markers for the interactive map (located artists only).
          get :map
          # Distinct regions/countries with counts, for filter facets.
          get :regions
        end
      end
      resources :posts, only: %i[index show]

      # Shops directory + pages. Like artists, :id may be a numeric id or a
      # handle; handles can contain dots (e.g. felipe.tattoo), so constrain to
      # "anything but a slash" and disable format parsing.
      get "shops", to: "shops#index"
      get "shops/:id", to: "shops#show", constraints: { id: %r{[^/]+} }, format: false

      # Follow-list discovery review queue. Handles can contain dots
      # (e.g. felipecesar.me), so constrain :handle to "anything but a slash"
      # and disable format parsing — otherwise Rails truncates at the dot.
      get "candidates", to: "candidates#index"
      post "candidates/:handle/approve", to: "candidates#approve",
           constraints: { handle: %r{[^/]+} }, format: false
      post "candidates/:handle/reject", to: "candidates#reject",
           constraints: { handle: %r{[^/]+} }, format: false
    end
  end
end
