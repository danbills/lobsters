# typed: false

# Handles the return from an OpenID Connect provider after OmniAuth has verified the response
# (state, nonce, PKCE, ID token signature). See OidcProvider and config/initializers/omniauth.rb.
class OidcController < ApplicationController
  include OidcSession

  # The IdP redirects here; OmniAuth already checked the OAuth state parameter.
  skip_forgery_protection only: :callback
  before_action :check_for_read_only_mode
  skip_after_action :clear_session_cookie

  def callback
    auth = request.env["omniauth.auth"]
    provider = OidcProvider.find(params[:provider])
    claims = oidc_claims(auth)
    if auth.blank? || provider.nil? || claims["sub"].blank?
      return login_failed("Login failed, please try again.")
    end

    if !provider.authorized?(claims)
      return login_failed("Your #{provider.label} account is not allowed to log in here.")
    end

    identity = UserIdentity.for_claims(provider, claims)

    # already logged in: this is linking another provider or re-authenticating
    return link_or_reauth(provider, identity, claims, auth) if @user

    user = identity&.user

    if !user && provider.trust_email_verified && oidc_email_verified?(claims) &&
        claims["email"].present?
      user = User.find_by(email: claims["email"].to_s)
      identity = create_identity(user, provider, claims) if user
    end

    if !user
      stash_pending_identity(provider, claims, oidc_session_data(provider, auth))
      return redirect_to signup_complete_path
    end

    if (reason = refuse_reason(user))
      return login_failed(reason)
    end

    reactivate(user) if user.deleted_at?
    sync_email(user, claims)
    identity.update!(last_login_at: Time.current)

    redirect_path = start_oidc_session(user, oidc_session_data(provider, auth))
    redirect_to safe_redirect(redirect_path)
  end

  def failure
    login_failed("Login with your identity provider failed (#{params[:message].to_s.gsub(/[^a-z_]/, "")}).")
  end

  private

  def link_or_reauth(provider, identity, claims, auth)
    if identity && identity.user_id != @user.id
      flash[:error] = "That #{provider.label} account is already linked to a different user."
      return redirect_to settings_path
    end

    if identity
      flash[:success] = "Confirmed it's you."
    else
      identity = create_identity(@user, provider, claims)
      flash[:success] = "Linked your #{provider.label} account."
    end
    identity.update!(last_login_at: Time.current)

    session[:oidc] = oidc_session_data(provider, auth)
    session[:authed_at] = Time.now.to_i
    redirect_to session.delete(:after_reauth).presence || settings_path
  end

  def create_identity(user, provider, claims)
    user.identities.create!(
      provider: provider.name,
      issuer: provider.issuer,
      subject: claims["sub"].to_s,
      email: claims["email"].to_s.presence&.slice(0, 100)
    )
  end

  # same rules as the old password login
  def refuse_reason(user)
    if user.is_wiped?
      "Your account was banned or deleted before the site changed admins. " \
        "Your email and password hash were wiped for privacy."
    elsif user.is_banned?
      ModNote.tattle_on_banned_login(user)
      "Your account has been banned. Log: #{user.banned_reason}"
    end
  end

  # Logging in again reactivates a self-deactivated account, like a password reset used to.
  def reactivate(user)
    user.update!(deleted_at: nil)
    Moderation.create!(moderator: nil, user: user, action: "reactivated")
    flash[:success] = "Welcome back, your account has been reactivated."
  end

  # The IdP is the source of truth for email addresses, but only verified ones.
  def sync_email(user, claims)
    email = claims["email"].to_s
    return if email.blank? || !oidc_email_verified?(claims) || email.casecmp?(user.email.to_s)

    if !user.update(email: email)
      flash[:error] = "Your identity provider's email address #{email} could not be saved: " \
        "#{user.errors.full_messages.to_sentence}"
      user.reload
    end
  end

  def safe_redirect(path)
    path = path.to_s
    (path.start_with?("/") && !path.start_with?("//")) ? path : "/"
  end

  def login_failed(message)
    flash[:error] = message
    redirect_to login_path
  end
end
