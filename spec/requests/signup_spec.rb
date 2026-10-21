# typed: false

require "rails_helper"

describe "signup", type: :request do
  let!(:inactive_user) { create(:user, :inactive) }
  let(:sender) { create(:user) }
  let(:invitation) { create(:invitation, user: sender) }

  describe "tattling on logged-in users who visit invite URLs" do
    before { sign_in sender }

    it "creates a ModNote" do
      expect {
        get "/invitations/#{invitation.code}"
      }.to change { ModNote.count }.by(2) # one on inviter, one on invitee (though redundnant here)
    end
  end

  def sign_up_through_provider(username: "new_user")
    get "/invitations/#{invitation.code}"
    expect(response.body).to include("Continue with Keycloak")
    mock_oidc_auth(sub: "brand-new", email: "new_user@example.com", username: "suggested")
    oidc_login
    expect(response).to redirect_to("/signup/complete")
    get "/signup/complete"
    expect(response.body).to include("suggested")
    post "/signup/complete", params: {user: {username: username, about: "hi"}}
  end

  it "creates the user, identity, and records a Username" do
    sign_up_through_provider

    user = User.find_by!(username: "new_user")
    expect(user.email).to eq("new_user@example.com")
    expect(user.invited_by_user).to eq(sender)
    expect(user.identities.sole).to have_attributes(provider: "keycloak", subject: "brand-new")
    expect(invitation.reload.new_user).to eq(user)
    expect(session[:u]).to eq(user.session_token)

    username = Username.last
    expect(username.username).to eq("new_user")
    expect(username.created_at).to eq(username.user.created_at)
    expect(username.renamed_away_at).to be_nil
  end

  it "re-renders on an invalid username without creating anything" do
    invitation # create the sender first
    expect { sign_up_through_provider(username: "a b") }.not_to change { User.count }
    expect(UserIdentity.count).to eq(0)
    expect(invitation.reload.used_at).to be_nil
    expect(response.body).to include("Username")
  end

  it "refuses an IdP login without an invitation" do
    mock_oidc_auth(sub: "uninvited", email: "uninvited@example.com")
    oidc_login
    get "/signup/complete"
    expect(response).to have_http_status(:forbidden)
    post "/signup/complete", params: {user: {username: "uninvited"}}
    expect(response).to have_http_status(:forbidden)
    expect(User.find_by(username: "uninvited")).to be_nil
  end

  it "requires a fresh IdP login" do
    get "/signup/complete"
    expect(response).to redirect_to("/login")
  end
end
