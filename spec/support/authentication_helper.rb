# typed: false

# Login goes through an OIDC provider; in specs OmniAuth's test mode stands in for it, using the
# provider configured in config/environments/test.rb.
module AuthenticationHelper
  module Oidc
    PROVIDER = "keycloak"

    def oidc_provider
      OidcProvider.find(PROVIDER)
    end

    # the identity a user logs in with, created if they don't have one yet
    def oidc_identity_for(user)
      user.identities.first || user.identities.create!(
        provider: PROVIDER,
        issuer: oidc_provider.issuer,
        subject: "sub-#{user.id}-#{SecureRandom.hex(4)}",
        email: user.email
      )
    end

    def mock_oidc_auth(sub:, email: nil, email_verified: true, username: nil, groups: nil)
      claims = {
        "iss" => oidc_provider.issuer,
        "sub" => sub,
        "email" => email,
        "email_verified" => email_verified,
        "preferred_username" => username
      }
      claims["groups"] = groups if groups
      OmniAuth.config.mock_auth[PROVIDER.to_sym] = OmniAuth::AuthHash.new(
        provider: PROVIDER,
        uid: sub,
        info: {email: email, email_verified: email_verified, nickname: username},
        extra: {raw_info: claims},
        credentials: {id_token: "test-id-token"}
      )
    end

    def mock_oidc_auth_for(user)
      identity = oidc_identity_for(user)
      mock_oidc_auth(sub: identity.subject, email: user.email, username: user.username)
    end
  end

  module ControllerHelper
    def stub_login_as user
      session[:u] = user.session_token
      session[:authed_at] = Time.now.to_i
    end
  end

  module FeatureHelper
    include Oidc

    def stub_login_as user
      mock_oidc_auth_for(user)
      visit "/login"
      click_button "Log in with Keycloak"
    end
  end

  module RequestHelper
    include Oidc

    def sign_in user
      mock_oidc_auth_for(user)
      post "/auth/#{PROVIDER}"
      follow_redirect! # to the callback, which logs in
    end

    # runs the OmniAuth request + callback phases for whatever mock_oidc_auth set up
    def oidc_login
      post "/auth/#{PROVIDER}"
      follow_redirect!
    end
  end
end
