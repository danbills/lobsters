# typed: false

# Shared by OidcController and SignupController for turning a verified OIDC login into a session.
module OidcSession
  extend ActiveSupport::Concern

  PENDING_IDENTITY_TTL = 15.minutes
  # the id_token is kept for RP-initiated logout; skip it if it would bloat the cookie session
  MAX_STORED_ID_TOKEN = 2000

  private

  def oidc_claims(auth)
    auth&.extra&.raw_info.to_h.deep_stringify_keys
  end

  def oidc_email_verified?(claims)
    claims["email_verified"] == true || claims["email_verified"].to_s == "true"
  end

  def oidc_session_data(provider, auth)
    id_token = auth&.credentials&.id_token.to_s
    {
      "provider" => provider.name,
      "id_token" => (id_token.bytesize <= MAX_STORED_ID_TOKEN) ? id_token : nil
    }
  end

  # Log the user in, keeping where they were headed. Resets the session against fixation.
  def start_oidc_session(user, oidc_data)
    redirect_to_path = session[:redirect_to]
    reset_session
    session[:u] = user.session_token
    session[:oidc] = oidc_data
    session[:authed_at] = Time.now.to_i
    redirect_to_path
  end

  def stash_pending_identity(provider, claims, oidc_data)
    session[:pending_identity] = {
      "provider" => provider.name,
      "subject" => claims["sub"].to_s,
      "email" => claims["email"].to_s.presence,
      "email_verified" => oidc_email_verified?(claims),
      "suggested_username" => provider.suggested_username(claims),
      "oidc" => oidc_data,
      "expires_at" => PENDING_IDENTITY_TTL.from_now.to_i
    }
  end

  def pending_identity
    pending = session[:pending_identity]
    return nil if pending.blank?

    if pending["expires_at"].to_i < Time.now.to_i || OidcProvider.find(pending["provider"]).nil?
      session.delete(:pending_identity)
      return nil
    end
    pending
  end
end
