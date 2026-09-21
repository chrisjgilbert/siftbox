Rails.application.routes.draw do
  # No show of its own: a post is read on the blog that published it, and the
  # archive links straight out. What this app serves is the images it fetched
  # off the publisher's CDN so the reader's browser never has to.
  resources :blog_posts, only: [] do
    resources :images, only: :show, module: :blog_posts
  end
  # No index: the roster is a section of the Subscriptions page, which is
  # where the reader already goes to see what reaches them and what does not.
  # Adding one here would be a second answer to the same question.
  # Muting is not removing, so it is a resource of its own rather than an
  # update to the blog: destroy takes the posts and the citations naming them,
  # creating a silence takes nothing and can be undone.
  resources :blogs, only: [ :create, :destroy ] do
    resource :silence, only: [ :create, :destroy ], module: :blogs
  end
  resources :editions, only: [ :index, :show ]
  # Singular: there is one public page, and what it shows is fixed. It is the
  # root as well, which is the only address it is reached at in practice —
  # named here so the page is a resource rather than a bare root.
  resource :landing, only: :show
  # No index of its own: a muted sender is a row of the roster on the
  # Subscriptions page, which is where the reader already goes to see what
  # reaches them. Only the way back is addressed here — the way in is a
  # silence on the issue the reader is reading, below.
  resources :newsletter_senders, only: [] do
    resource :silence, only: :destroy, module: :newsletter_senders
  end
  resources :newsletters, only: :index do
    # The two ways out of the pen, as nouns: creating a dismissal is the
    # reader saying the confirmation is dealt with, creating a release is them
    # saying it was content all along. Verbs on the newsletter would be the
    # missing nouns .claude/rules/controllers.md warns about.
    resource :dismissal, only: :create, module: :newsletters
    resources :images, only: :show, module: :newsletters
    resource :original, only: :show, module: :newsletters
    resource :release, only: :create, module: :newsletters
    # Muting the sender, from an issue they sent. Nested under the newsletter
    # because that is what the reader is looking at when they decide; what it
    # mutes is the address on it, which is Newsletter::Sender's business.
    resource :silence, only: :create, module: :newsletters
    resource :source, only: :show, module: :newsletters
  end
  # Singular, and the token travels as a parameter rather than a path
  # segment: config.filter_parameters redacts query and body parameters and
  # never the path, so a token routed as :id reaches the log verbatim.
  resource :password, only: [ :new, :create, :edit, :update ]
  resource :session, only: [ :new, :create, :destroy ]
  resource :settings, only: :show
  # An index, because the page is a list of what is waiting. Dismissing and
  # releasing a hold are nested resources under a newsletter rather than verbs
  # here — the pen is a view of the mail, not a place mail lives.
  resources :subscriptions, only: :index

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # A signed-out visitor always gets the project page: what siftbox is, a
  # morning's edition and where the source lives. A signed-in reader is sent
  # on to the latest edition — the edition is the app — or to the editions
  # archive on a morning before the first one has been composed.
  root "landings#show"
end
