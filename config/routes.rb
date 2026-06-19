Rails.application.routes.draw do
    root 'posts#index'

    get '/theidea', to: 'landing#idea', as: 'idea'
    get '/theproject', to: 'landing#project', as: 'project'

    get '/login', to: 'sessions#new', as: "login"
    post '/sessions', to: 'sessions#create', as: "sessions"
    get '/logout', to: 'sessions#destroy', as: "logout"

    get "/artists", to: "artists#index", as: "artists"
    get "/artists/:id", to: "artists#show", as: "artist"

    get "/users", to: "users#index", as: "users"
    get "/posts", to: "posts#index", as: "posts"
    get "/posts/:id", to: "posts#show", as: "post"
    get "/users/new", to: "users#new", as: "new_user"
    get "/users/:id", to:"users#show", as: "user"
    post "/users", to: "users#create"
    get "/users/:id/edit", to: "users#edit", as: "edit_user"
    patch "/users/:id", to: "users#update"
    delete "/users/:id", to: "users#destroy", as: "destroy_user"

    resources :favorite_posts, only: [:create, :destroy]



end
