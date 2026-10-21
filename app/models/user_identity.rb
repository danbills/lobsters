# typed: false

# Links a User to an account at an OpenID Connect provider. Matched on (issuer, subject), which
# the provider guarantees is stable and unique, never on email or username.
class UserIdentity < ApplicationRecord
  belongs_to :user

  validates :provider, :issuer, :subject, presence: true, length: {maximum: 255}
  validates :email, length: {maximum: 100}, allow_nil: true
  validates :subject, uniqueness: {scope: :issuer}

  def self.for_claims(provider, claims)
    find_by(issuer: provider.issuer, subject: claims["sub"].to_s)
  end

  def oidc_provider
    OidcProvider.find(provider)
  end

  def provider_label
    oidc_provider&.label || provider
  end
end
