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
    end
  end
end
