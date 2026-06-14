Rails.application.routes.draw do
  root "pages#home"

  # Legal/info pages
  get "terms", to: "pages#terms", as: :terms
  get "privacy", to: "pages#privacy", as: :privacy
  get "cookies", to: "pages#cookies", as: :cookies

  # Auth
  get "login", to: "sessions#new", as: :login
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout
  get "register", to: "registrations#new", as: :register
  post "register", to: "registrations#create"

  # Invitations
  get "invitations/:token/accept", to: "invitations#accept", as: :accept_invitation

  # Password resets
  get "password/forgot", to: "password_resets#new", as: :forgot_password
  post "password/forgot", to: "password_resets#create"
  get "password/reset/:token", to: "password_resets#edit", as: :reset_password
  patch "password/reset/:token", to: "password_resets#update"

  # Profile
  resource :profile, only: [:edit, :update, :destroy]

  # Public share viewer
  get "s/:token", to: "public_shares#show", as: :public_share

  # Admin
  namespace :admin do
    root to: "dashboard#index"
    resources :users, only: [:index, :show, :new, :create, :edit, :update, :destroy]
    resources :spam_numbers
  end

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Internal JSON API for trusted services on the same private network
  # (e.g., callscreen for inbound-call contact lookups). Bearer-token auth.
  namespace :api, defaults: { format: :json } do
    get  "health",         to: "health#show"
    get  "contact_lookup", to: "contact_lookups#show"
    post "spam_reports",   to: "spam_reports#create"
  end

  # All contacts view
  get "contacts", to: "contacts#index", as: :all_contacts

  # Addressbooks and nested contacts
  resources :addressbooks, param: :uri do
    resources :contacts, param: :uri, except: [:index], constraints: { uri: /[^\/]+/ } do
      member do
        get :export
      end
    end

    resources :shares, only: [:create, :destroy], controller: "addressbook_shares"
    resources :groups, only: [:create, :update, :destroy], controller: "contact_groups"

    member do
      get :export
      post :import
      post :regenerate_dav_password
      post :create_public_link, controller: "addressbook_shares"
      delete :destroy_public_link, controller: "addressbook_shares"
    end
  end
end
