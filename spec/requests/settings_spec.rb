# typed: false

require "rails_helper"

describe "settings", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "shows linked logins and no password fields" do
    get "/settings"
    expect(response.body).to include("Keycloak")
    expect(response.body).not_to include("New Password")
  end

  it "doesn't let users change their email" do
    expect {
      post "/settings", params: {user: {email: "new@example.com"}}
    }.not_to change { user.reload.email }
  end

  describe "sensitive actions" do
    it "asks for a fresh login when the last one is old" do
      travel 11.minutes do
        post "/settings/deactivate", params: {user: {i_am_sure: "1"}}
        expect(response).to redirect_to("/login/reauth")
        expect(user.reload.deleted_at).to be_nil

        get "/login/reauth"
        expect(response.body).to include("Confirm with Keycloak")

        oidc_login # mock_auth is still this user's
        expect(response).to redirect_to("/settings")

        post "/settings/deactivate", params: {user: {i_am_sure: "1"}}
        expect(user.reload.deleted_at).to be_present
      end
    end

    it "won't unlink the only login" do
      identity = user.identities.sole
      post "/settings/identities/#{identity.id}/unlink"
      expect(flash[:error]).to match(/only login/)
      expect(UserIdentity.exists?(identity.id)).to be true
    end

    it "unlinks one of several logins" do
      second = user.identities.create!(provider: "keycloak", issuer: "https://idp.example.com/realms/test", subject: "second")
      post "/settings/identities/#{second.id}/unlink"
      expect(UserIdentity.exists?(second.id)).to be false
    end
  end
end
