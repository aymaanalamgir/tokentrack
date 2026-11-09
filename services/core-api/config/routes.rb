Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"
      get "demo/identities", to: "demo#identities"
      post "demo/sessions", to: "demo#create"
      delete "demo/session", to: "demo#destroy"
      get "me", to: "me#show"
      get "me/access", to: "me#access"
      get "me/overview", to: "me#overview"
      resources :organizations, only: :show
      resources :organizational_units, path: "organizational-units", only: [:index, :show]
      resources :users, only: [:index, :show] do
        get "reporting-context", on: :member, action: :reporting_context
      end
      resources :projects, only: [:index, :show, :update]
    end
  end
end
