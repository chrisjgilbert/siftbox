Rails.application.routes.draw do
  resources :newsletters, only: [ :index, :show ] do
    resource :original, only: :show, module: :newsletters
    resource :read, only: :destroy, module: :newsletters
    resource :source, only: :show, module: :newsletters
  end
  resources :passwords, param: :token, only: [ :new, :create, :edit, :update ]
  resource :session, only: [ :new, :create, :destroy ]

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "newsletters#index"
end
