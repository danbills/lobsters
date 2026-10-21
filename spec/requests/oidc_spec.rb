# typed: false

require "rails_helper"

describe "OIDC login", type: :request do
  let!(:inactive_user) { create(:user, :inactive) }
  let(:user) { create(:user) }

  describe "GET /login" do
    it "shows a button per provider" do
      get "/login"
      expect(response.body).to include("Log in with Keycloak")
      expect(response.body).not_to include("Password")
    end

    it "redirects logged-in users" do
      sign_in user
      get "/login"
      expect(response).to redirect_to("/")
    end
  end

  describe "existing identity" do
    it "logs in" do
      sign_in user
      expect(response).to redirect_to("/")
      expect(session[:u]).to eq(user.session_token)
      expect(session[:oidc]).to include("provider" => "keycloak", "id_token" => "test-id-token")
      expect(user.identities.first.last_login_at).to be_present
    end

    it "returns to the page that required login" do
      get "/settings"
      expect(response).to redirect_to("/login")
      sign_in user
      expect(response).to redirect_to("/settings")
    end

    it "updates the user's email from a verified claim" do
      identity = oidc_identity_for(user)
      mock_oidc_auth(sub: identity.subject, email: "changed@example.com")
      oidc_login
      expect(user.reload.email).to eq("changed@example.com")
    end

    it "ignores an unverified email claim" do
      identity = oidc_identity_for(user)
      mock_oidc_auth(sub: identity.subject, email: "changed@example.com", email_verified: false)
      oidc_login
      expect(user.reload.email).not_to eq("changed@example.com")
    end
  end

  describe "first login of an existing user" do
    it "links by verified email" do
      mock_oidc_auth(sub: "new-sub", email: user.email)
      expect { oidc_login }.to change { user.identities.count }.by(1)
      expect(session[:u]).to eq(user.session_token)
      expect(user.identities.first).to have_attributes(subject: "new-sub", issuer: "https://idp.example.com/realms/test")
    end

    it "doesn't link by unverified email" do
      mock_oidc_auth(sub: "new-sub", email: user.email, email_verified: false)
      expect { oidc_login }.not_to change { UserIdentity.count }
      expect(session[:u]).to be_nil
      expect(response).to redirect_to("/signup/complete")
    end
  end

  describe "refused logins" do
    it "refuses banned users and tattles" do
      banned = create(:user, :banned)
      mock_oidc_auth_for(banned)
      expect { oidc_login }.to change { ModNote.count }.by(1)
      expect(session[:u]).to be_nil
      expect(flash[:error]).to match(/banned/)
    end

    it "refuses wiped users" do
      wiped = create(:user, :banned, :wiped)
      mock_oidc_auth_for(wiped)
      oidc_login
      expect(session[:u]).to be_nil
      expect(flash[:error]).to match(/wiped/)
    end

    it "refuses users missing the required group" do
      allow(OidcProvider.find("keycloak")).to receive(:required_group).and_return("lobsters")
      identity = oidc_identity_for(user)
      mock_oidc_auth(sub: identity.subject, groups: ["/other"])
      oidc_login
      expect(session[:u]).to be_nil
      expect(flash[:error]).to match(/not allowed/)

      mock_oidc_auth(sub: identity.subject, groups: ["/lobsters"])
      oidc_login
      expect(session[:u]).to eq(user.session_token)
    end

    it "handles provider failures" do
      OmniAuth.config.mock_auth[:keycloak] = :invalid_credentials
      post "/auth/keycloak"
      follow_redirect! # callback fails
      follow_redirect! # to /auth/failure
      expect(response).to redirect_to("/login")
      expect(flash[:error]).to match(/invalid_credentials/)
    end
  end

  it "reactivates deactivated users" do
    deactivated = create(:user, :deactivated)
    mock_oidc_auth_for(deactivated)
    oidc_login
    expect(session[:u]).to eq(deactivated.session_token)
    expect(deactivated.reload.deleted_at).to be_nil
    expect(Moderation.last.action).to eq("reactivated")
  end

  describe "logout" do
    it "clears the session and goes to the provider's end_session_endpoint" do
      sign_in user
      allow_any_instance_of(OidcProvider).to receive(:end_session_url)
        .with(id_token: "test-id-token", post_logout_redirect_uri: "http://www.example.com/")
        .and_return("https://idp.example.com/logout?id_token_hint=test-id-token")
      post "/logout"
      expect(response).to redirect_to("https://idp.example.com/logout?id_token_hint=test-id-token")
      expect(session[:u]).to be_nil
    end

    it "falls back to the homepage when the provider has no end_session_endpoint" do
      sign_in user
      allow_any_instance_of(OidcProvider).to receive(:end_session_url).and_return(nil)
      post "/logout"
      expect(response).to redirect_to("/")
    end
  end

  describe "while logged in" do
    it "links another account of the same provider" do
      sign_in user
      mock_oidc_auth(sub: "second-sub", email: "other@example.com")
      expect { oidc_login }.to change { user.identities.count }.by(1)
      expect(response).to redirect_to("/settings")
    end

    it "won't link an identity that belongs to someone else" do
      other = create(:user)
      other_identity = oidc_identity_for(other)
      sign_in user
      mock_oidc_auth(sub: other_identity.subject)
      expect { oidc_login }.not_to change { UserIdentity.count }
      expect(flash[:error]).to match(/different user/)
    end
  end
end

describe "OidcProvider" do
  let(:provider) { OidcProvider.find("keycloak") }

  it "suggests a valid, unused username" do
    create(:user, username: "alice")
    expect(provider.suggested_username("preferred_username" => "alice")).to eq("alice2")
    expect(provider.suggested_username("preferred_username" => "bob.smith@example.com")).to eq("bobsmith")
    expect(provider.suggested_username("preferred_username" => "admin")).to eq("admin2")
    expect(provider.suggested_username("preferred_username" => "")).to be_nil
  end

  it "builds the callback URL from base_url" do
    expect(provider.redirect_uri).to eq("http://www.example.com/auth/keycloak/callback")
  end
end
