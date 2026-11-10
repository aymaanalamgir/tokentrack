Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      namespace :internal do
        post "priced-usage-events", to: "priced_usage_events#create"
        post "financial-reconciliation", to: "priced_usage_events#reconcile"
        post "usage-references/validate", to: "usage_references#validate"
        get "usage-references/demo-snapshot", to: "usage_references#demo_snapshot"
      end
      get "budgets", to: "budgets#show"
      post "budgets/transfers", to: "budgets#transfer"
      post "budgets/funding", to: "budgets#fund"
      post "budgets/periods", to: "budgets#initialize_month"
      post "budgets/ceilings", to: "budgets#ceiling"
      post "budgets/allocations", to: "budgets#allocations"
      post "budgets/delegations", to: "budgets#delegate"
      post "budgets/delegations/revoke", to: "budgets#revoke"
      get "analytics", to: "analytics#show"
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
      resources :projects, only: [:index, :show, :create, :update] do
        get "eligible-users", on: :collection, action: :eligible_users
        get "eligible-users", on: :member, action: :eligible_users
        get "team-groups", on: :member, action: :team_groups
        post "transfer-ownership", on: :member, action: :transfer_ownership
        resources :memberships, controller: :project_memberships, only: [:index, :create, :update, :destroy]
      end
    end
  end
end
