# typed: false

# OpenID Connect login, one OmniAuth strategy per provider in credentials (see OidcProvider).
# Login is started by POST /auth/:provider (omniauth-rails_csrf_protection checks the CSRF token).

OmniAuth.config.allowed_request_methods = [:post]
OmniAuth.config.logger = Rails.logger
OmniAuth.config.on_failure = proc do |env|
  message = Rack::Utils.escape(env["omniauth.error.type"].to_s)
  Rack::Response.new([], 302, "Location" => "/auth/failure?message=#{message}").finish
end

Rails.application.config.middleware.use OmniAuth::Builder do
  OidcProvider.all.each do |p| # standard:disable Rails/FindEach -- an Array, not a query
    provider :openid_connect, p.omniauth_options
  end
end
