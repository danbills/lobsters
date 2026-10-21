# typed: false

# An OpenID Connect identity provider (Keycloak, Okta, ...) configured in credentials:
#
#   oidc:
#     base_url: "https://example.org"   # optional, defaults to Rails.application.root_url
#     providers:
#       keycloak:
#         label: "Keycloak"
#         issuer: "https://idp.example.org/realms/example"
#         client_id: "lobsters"
#         client_secret: "..."
#
# Each provider gets the routes /auth/:name (POST, starts login) and /auth/:name/callback.
# Adding or swapping a provider is a config change, see config/credentials.yml.enc.sample.
class OidcProvider
  ATTRIBUTES = %i[name label issuer client_id client_secret username_claim
    trust_email_verified groups_claim required_group].freeze
  attr_reader(*ATTRIBUTES)

  # config.x.oidc (set in config/environments/test.rb) overrides credentials
  def self.config
    Rails.application.config.x.oidc.presence || Rails.application.credentials.oidc || {}
  end

  def self.all
    @all ||= (config[:providers] || {}).map { |name, provider_config|
      new(name: name.to_s, **provider_config.to_h.symbolize_keys.slice(*ATTRIBUTES))
    }
  end

  def self.find(name)
    all.find { |p| p.name == name.to_s }
  end

  def self.any?
    all.any?
  end

  def self.reset!
    @all = nil
  end

  def self.base_url
    (config[:base_url].presence ||
      Rails.application.root_url).chomp("/")
  end

  def initialize(name:, label: nil, issuer: nil, client_id: nil, client_secret: nil,
    username_claim: "preferred_username", trust_email_verified: false,
    groups_claim: "groups", required_group: nil)
    @name = name
    @label = label.presence || name.titleize
    @issuer = issuer
    @client_id = client_id
    @client_secret = client_secret
    @username_claim = username_claim.presence || "preferred_username"
    @trust_email_verified = trust_email_verified == true
    @groups_claim = groups_claim.presence || "groups"
    @required_group = required_group.presence
  end

  def start_path
    "/auth/#{name}"
  end

  def redirect_uri
    "#{OidcProvider.base_url}/auth/#{name}/callback"
  end

  # options for the omniauth_openid_connect strategy
  def omniauth_options
    {
      name: name.to_sym,
      issuer: issuer,
      discovery: true,
      pkce: true,
      response_type: :code,
      scope: %i[openid email profile],
      uid_field: "sub",
      allow_authorize_params: %i[prompt max_age],
      client_options: {
        identifier: client_id,
        secret: client_secret,
        redirect_uri: redirect_uri
      }
    }
  end

  # claims is the merged ID token + userinfo hash (omniauth's extra.raw_info)
  def authorized?(claims)
    return true if required_group.nil?

    Array(claims[groups_claim]).map { |g| g.to_s.delete_prefix("/") }.include?(required_group)
  end

  # A starting point for the username field at signup, the user can change it.
  def suggested_username(claims)
    raw = claims[username_claim].to_s
    raw = raw.split("@").first.to_s if raw.include?("@") # Okta sends the login, an email
    raw = raw.gsub(/[^A-Za-z0-9_-]/, "").sub(/\A[_-]+/, "")[0, 24]
    return nil if raw.blank?

    candidate = raw
    n = 1
    while User.exists?(username: candidate) || Username.where(username: candidate).exists? ||
        UsernameAttribute::BANNED_USERNAMES.include?(candidate.downcase)
      n += 1
      candidate = "#{raw[0, 24 - n.to_s.length]}#{n}"
    end
    candidate
  end

  def end_session_url(id_token:, post_logout_redirect_uri:)
    endpoint = discovery&.end_session_endpoint
    return nil if endpoint.blank?

    uri = URI(endpoint)
    query = URI.decode_www_form(uri.query.to_s)
    query << ["id_token_hint", id_token] if id_token.present?
    query << ["client_id", client_id]
    query << ["post_logout_redirect_uri", post_logout_redirect_uri]
    uri.query = URI.encode_www_form(query)
    uri.to_s
  end

  private

  def discovery
    @discovery ||= ::OpenIDConnect::Discovery::Provider::Config.discover!(issuer)
  rescue => e
    Rails.logger.warn "OIDC discovery failed for #{name}: #{e.class} #{e.message}"
    nil
  end
end
