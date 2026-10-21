# typed: false

DOMAINS_IDENTIFIER = /([^\/]+?)(?=\.json|\.rss|$|\/)/ # match example.com but not example.com.rss
ORIGINS_IDENTIFIER = /(.+)(?=\.json|\.rss|$|\/)/ # match github.com/user but not github.com/user.rss

Rails.application.routes.draw do
  root to: "home#index",
    protocol: (Rails.application.config.force_ssl ? "https://" : "http://"),
    as: "root"

  get "/404" => "about#four_oh_four", :via => :all

  get "/rss" => "home#index", :format => "rss"
  get "/hottest" => "home#index", :format => "json"

  get "/page/:page" => "home#index"

  get "/active" => "home#active"
  get "/active/page/:page" => "home#active"
  get "/newest" => "home#newest"
  get "/newest/page/:page" => "home#newest"
  get "/recent" => "home#recent"
  get "/recent/page/:page" => "home#recent"
  get "/hidden" => "home#hidden"
  get "/hidden/page/:page" => "home#hidden"

  get "/saved" => "home#saved"
  get "/saved/page/:page" => "home#saved"
  get "/upvoted/stories" => "home#upvoted"
  get "/upvoted/stories/page/:page" => "home#upvoted"
  get "/upvoted/comments" => "comments#upvoted"
  get "/upvoted/comments/page/:page" => "comments#upvoted"
  get "/upvoted", to: redirect("/upvoted/stories")
  get "/upvoted/page/:page", to: redirect("/upvoted/stories/page/%{page}")

  get "/top/rss", to: redirect("/top.rss", status: 301)
  get "/top/:length/rss", to: redirect("/top/%{length}.rss", status: 301)
  get "/top(/:length(/page/:page))" => "home#top", :as => "top"

  get "/threads" => "comments#user_threads"

  get "/replies", to: redirect("/inbox/all")
  get "/replies/page/:page", to: redirect("/inbox/all")
  get "/replies/comments", to: redirect("/inbox/all")
  get "/replies/comments/page/:page", to: redirect("/inbox/all")
  get "/replies/stories", to: redirect("/inbox/all")
  get "/replies/stories/page/:page", to: redirect("/inbox/all")
  get "/replies/unread", to: redirect("/inbox/unread")
  get "/replies/unread/page/:page", to: redirect("/inbox/unread")

  get "/login" => "login#index"
  post "/logout" => "login#logout"
  get "/login/reauth" => "login#reauth", :as => "reauth"

  # POST /auth/:provider is handled by the OmniAuth middleware, see config/initializers/omniauth.rb
  match "/auth/:provider/callback" => "oidc#callback", :via => [:get, :post], :as => "oidc_callback"
  get "/auth/failure" => "oidc#failure"

  get "/signup" => "signup#index"
  get "/signup/invite" => "signup#invite"
  get "/signup/complete" => "signup#complete", :as => "signup_complete"
  post "/signup/complete" => "signup#create"

  get "/t/:tag" => "home#single_tag", :as => "tag", :constraints => {tag: /[^,.\/]+/}
  get "/t/:tag/page/:page" => "home#single_tag", :constraints => {tag: /[^,.\/]+/}
  get "/t/:tag" => "home#multi_tag", :as => "multi_tag"
  get "/t/:tag/page/:page" => "home#multi_tag"

  constraints id: DOMAINS_IDENTIFIER do
    get "/domain/:id(.:format)", to: redirect("/domains/%{id}")
    get "/domain/:id/page/:page", to: redirect("/domains/%{id}/page/%{page}")
    get "/domains/:id(.:format)" => "home#for_domain", :as => "domain"
    get "/domains/:id/page/:page" => "home#for_domain"
    get "/domains/:id/origins" => "origins#for_domain", :as => "domain_origins"
    get "/domains/:id/:author", to: redirect("/origins/%{id}/%{author}")
    get "/domain/:domain/:identifier(.:format)", to: redirect("/domains/%{domain}/%{identifier}")
    get "/domain/:domain/:identifier/page/:page", to: redirect("/domains/%{domain}/%{identifier}/page/%{page}")
  end

  constraints identifier: ORIGINS_IDENTIFIER do
    get "/origins/:identifier(.:format)" => "home#for_origin", :as => "origin"
  end

  get "/search" => "search#index"
  get "/search/:q" => "search#index"

  get "/stories/url/all" => "story_urls#all"
  get "/stories/url/latest" => "story_urls#latest"

  resources :stories, except: [:index] do
    get "/stories/:short_id", to: redirect("/s/%{short_id}")
    post "upvote"
    post "flag"
    post "unvote"
    patch "destroy"
    patch "undelete"
    post "hide"
    post "unhide"
    post "save"
    post "unsave"
    post "disown"
    resources :suggestions, only: [:new, :create]
  end
  post "/stories/fetch_url_attributes", format: "json"
  post "/stories/preview" => "stories#preview"
  post "/stories/check_url_dupe" => "stories#check_url_dupe"

  get "/comments/rss", to: redirect("/comments.rss")
  resources :comments, except: [:new, :destroy] do
    member do
      get "/comments/:id" => "comments#redirect_from_short_id"
      get "reply"
      post "upvote"
      post "flag"
      post "unvote"

      post "delete"
      post "undelete"
      post "disown"
    end
  end
  get "/comments/page/:page" => "comments#index"

  get "/messages/sent" => "messages#sent"
  get "/messages" => "messages#index"
  post "/messages/batch_delete" => "messages#batch_delete",
    :as => "batch_delete_messages"
  resources :messages, except: %i[new edit update] do
    post "keep_as_new"
    post "mod_note"
  end

  get "/inbox" => "inbox#index"
  get "/inbox/all(/page/:page)" => "inbox#all", :as => "inbox_all"
  get "/inbox/unread" => "inbox#unread"

  get "/c/:id.json" => "comments#show_short_id", :format => "json"
  get "/c/:id" => "comments#redirect_from_short_id", :as => "comment_short_id"

  # deprecated
  get "/s/:story_id/:title/comments/:id" => "comments#redirect_from_short_id"

  get "/s/:id/(:title)" => "stories#show", :as => "story_short_id"

  get "/users" => "users#tree", :as => "users_tree"
  get "/~:username" => "users#show", :as => "user"
  get "/~:username/standing" => "users#standing", :as => "user_standing"
  get "/~:user/stories(/page/:page)" => "home#newest_by_user", :as => "newest_by_user"
  get "/~:user/threads" => "comments#user_threads", :as => "user_threads"
  get "/~:user/comments.rss" => "comments#user_comments", :as => "user_comments", :format => "rss"

  post "/~:username/ban" => "users#ban", :as => "user_ban"
  post "/~:username/unban" => "users#unban", :as => "user_unban"
  post "/~:username/disable_invitation" => "users#disable_invitation",
    :as => "user_disable_invite"
  post "/~:username/enable_invitation" => "users#enable_invitation",
    :as => "user_enable_invite"

  # 2023-07 redirect /u to /~username and /users (for tree)
  get "/u", to: redirect("/users", status: 301)
  get "/u/:username", to: redirect("/~%{username}", status: 301)
  # we don't do /@alice but easy mistake with comments autolinking @alice
  get "/@:username", to: redirect("/~%{username}", status: 301)
  get "/u/:username/standing", to: redirect("~%{username}/standing", status: 301)
  get "/newest/:user", to: redirect("~%{user}/stories", status: 301)
  get "/newest/:user(/page/:page)", to: redirect("~%{user}/stories/page/%{page}", status: 301)
  get "/threads/:user", to: redirect("~%{user}/threads", status: 301)

  get "/avatars/:username_size.png" => "avatars#show"
  post "/avatars/expire" => "avatars#expire"

  get "/story_image/:short_id.png" => "story_image#show", :as => :story_image

  get "/settings" => "settings#index"
  post "/settings" => "settings#update"
  post "/settings/update_avatar_source" => "settings#update_avatar_source", :as => "update_avatar_source"
  post "/settings/deactivate" => "settings#deactivate", :as => "deactivate"
  post "/settings/identities/:id/unlink" => "settings#unlink_identity", :as => "unlink_identity"
  post "/settings/pushover_auth" => "settings#pushover_auth"
  get "/settings/pushover_callback" => "settings#pushover_callback"
  get "/settings/mastodon_authentication" => "settings#mastodon_authentication"
  get "/settings/mastodon_auth" => "settings#mastodon_auth"
  get "/settings/mastodon_callback" => "settings#mastodon_callback"
  post "/settings/mastodon_disconnect" => "settings#mastodon_disconnect"
  get "/settings/github_auth" => "settings#github_auth"
  get "/settings/github_callback" => "settings#github_callback"
  post "/settings/github_disconnect" => "settings#github_disconnect"

  get "/filters" => "filters#index"
  post "/filters" => "filters#update"

  get "/tags" => "tags#index"
  get "/tags.json" => "tags#index", :format => "json"

  get "/categories/new" => "categories#new", :as => "new_category"
  get "/categories/:category_name/edit" => "categories#edit", :as => "edit_category"
  get "/categories/:category" => "home#category", :as => :category
  post "/categories" => "categories#create"
  post "/categories/:category_name" => "categories#update", :as => "update_category"

  post "/invitations" => "invitations#create"
  get "/invitations" => "invitations#index"
  get "/invitations/request" => "invitations#build"
  post "/invitations/create_by_request" => "invitations#create_by_request",
    :as => "create_invitation_by_request"
  get "/invitations/confirm/:code" => "invitations#confirm_email"
  post "/invitations/send_for_request" => "invitations#send_for_request",
    :as => "send_invitation_for_request"
  get "/invitations/:invitation_code" => "signup#invited"
  post "/invitations/delete_request" => "invitations#delete_request",
    :as => "delete_invitation_request"

  resources :hat_requests, except: [:edit] do
    member do
      post :approve
      post :reject
    end
  end
  resources :hats, only: %i[index edit] do
    member do
      get :doff
      post :doff_by_user
      post :update_in_place
      post :update_by_recreating
    end
  end

  get "/moderations" => "moderations#index"
  get "/moderations/page/:page" => "moderations#index"
  get "/moderators" => "users#tree", :moderators => true

  resources :mod_mails, only: [:index, :show]
  resources :mod_mail_messages, only: :create

  namespace :mod do
    # dashboards
    get "/" => "activities#index", :as => "mod_activity"
    get "flagged_stories/:period" => "flagged#flagged_stories", :as => "flagged_stories"
    get "flagged_comments/:period" => "flagged#flagged_comments", :as => "flagged_comments"
    get "commenters/:period" => "flagged#commenters", :as => "commenters"

    # tools
    get "notes(/:period)", to: redirect("/mod/")
    post "notes" => "notes#create"

    # site data
    resources :comments, only: [:destroy]
    constraints id: DOMAINS_IDENTIFIER do
      resources :domains, only: [:create, :edit, :update]
      patch "/domains_ban/:id" => "domains_ban#update", :as => "ban_domain"
      post "/domains_ban/:id" => "domains_ban#create_and_ban", :as => "create_and_ban_domain"
    end
    constraints identifier: ORIGINS_IDENTIFIER do
      resources :origins, param: :identifier, only: %i[edit]
      patch "/origins_ban/:identifier" => "origins_ban#update", :as => "ban_origin"
      post "/origins_ban/:identifier" => "origins_ban#create_and_ban", :as => "create_and_ban_origin"
    end
    resources :mails, except: [:destroy], as: "mod_mails"
    resources :mail_messages, only: :create, as: "mod_mail_messages"
    resources :reparents, only: [:new, :create]
    resources :stories, only: [:edit, :update] do
      patch "undelete"
      patch "destroy"
    end
    resources :tags, only: [:create, :edit, :new, :update]
  end

  mount MissionControl::Jobs::Engine, at: "/jobs"

  get "/privacy" => "about#privacy"
  get "/about" => "about#about"
  get "/chat" => "about#chat"

  get "/stats" => "stats#index"

  get "/banned-ips" => "banned_ips#index"

  get "/cabinet" => "cabinet#index"
end
