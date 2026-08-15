Rails.application.routes.draw do
  resources :editions, only: [ :index, :show ]
  resources :newsletters, only: [ :index, :show ] do
    resources :images, only: :show, module: :newsletters
    resource :original, only: :show, module: :newsletters
    resource :read, only: :destroy, module: :newsletters
    resource :source, only: :show, module: :newsletters
  end
  # Singular, and the token travels as a parameter rather than a path
  # segment: config.filter_parameters redacts query and body parameters and
  # never the path, so a token routed as :id reaches the log verbatim.
  resource :password, only: [ :new, :create, :edit, :update ]
  resource :session, only: [ :new, :create, :destroy ]
  resource :waitlist_signup, only: [ :new, :create ]

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # The landing page is the new-signup form, so the public root and the
  # waitlist are one resource rather than a pages controller with a verb for
  # a name. A signed-in reader is sent on to the latest edition — the edition
  # is the app — or to the editions archive on a morning before the first one
  # has been composed.
  root "waitlist_signups#new"
end
