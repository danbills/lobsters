# typed: false

# Login is done by an OpenID Connect provider, see OidcController and OidcProvider.
class LoginController < ApplicationController
  before_action :authenticate_user
  before_action :check_for_read_only_mode, except: [:index]
  before_action :require_no_user_or_redirect, only: [:index]
  before_action :require_logged_in_user, only: [:reauth]
  before_action :show_title_h1
  skip_after_action :clear_session_cookie

  def logout
    oidc = session[:oidc]
    reset_session if @user

    provider = OidcProvider.find(oidc["provider"]) if oidc.is_a?(Hash)
    url = provider&.end_session_url(
      id_token: oidc["id_token"],
      post_logout_redirect_uri: "#{OidcProvider.base_url}/"
    )
    if url
      redirect_to url, allow_other_host: true
    else
      redirect_to "/"
    end
  end

  def index
    @title = "Login"
    @providers = OidcProvider.all
  end

  # Asks a logged-in user to log in again at their provider before a sensitive action.
  def reauth
    @title = "Confirm It's You"
    linked = @user.identities.map(&:provider)
    @providers = OidcProvider.all.select { |p| linked.include?(p.name) }
  end
end
