# typed: false

class SettingsController < ApplicationController
  before_action :require_logged_in_user, :show_title_h1
  before_action :require_recent_auth, only: [:deactivate, :unlink_identity]

  def index
    @title = "Settings"
    @edit_user = @user.dup
  end

  def deactivate
    unless params[:user][:i_am_sure] == "1"
      flash[:error] = 'You did not check the "I am sure" checkbox.'
      return redirect_to settings_path
    end
    disown = params[:user][:disown] == "1"
    @user.delete!
    InactiveUser.disown_all_by_author!(@user) if disown

    Moderation.create!(
      moderator: nil,
      user: @user,
      action: "deactivated#{", disowning their stories and comments" if disown}"
    )
    reset_session
    flash[:success] = "You have deactivated your account#{" and disowned your stories and comments." if disown}. Bye."
    redirect_to "/"
  end

  def update_avatar_source
    @user.expire_avatar!
    @user.update(user_params)
    flash[:success] = "Updated avatar preference."
    redirect_to "/settings"
  end

  def update
    @edit_user = @user.clone

    if @edit_user.update(user_params)
      if @edit_user.username_previously_changed?
        Username.rename!(
          user: @edit_user,
          from: @edit_user.username_previously_was,
          to: @edit_user.username,
          by: @user
        )
      end
      flash.now[:success] = "Successfully updated settings."
      @user = @edit_user
    end

    render action: "index"
  end

  def unlink_identity
    identity = @user.identities.find(params[:id])
    if @user.identities.count <= 1
      flash[:error] = "You can't unlink your only login, you'd be locked out."
    else
      identity.destroy!
      flash[:success] = "Unlinked your #{identity.provider_label} login."
    end
    redirect_to settings_path
  end

  # external services

  def pushover_auth
    if !Pushover.enabled?
      flash[:error] = "This site is not configured for Pushover"
      return redirect_to "/settings"
    end

    session[:pushover_rand] = SecureRandom.hex

    redirect_to Pushover.subscription_url(
      success: "#{Rails.application.root_url}settings/pushover_callback?" \
        "rand=#{session[:pushover_rand]}",
      failure: "#{Rails.application.root_url}settings/"
    ), allow_other_host: true
  end

  def pushover_callback
    if session[:pushover_rand].to_s.blank?
      flash[:error] = "No random token present in session"
      return redirect_to "/settings"
    end

    if params[:rand].to_s.blank?
      flash[:error] = "No random token present in URL"
      return redirect_to "/settings"
    end

    if params[:rand].to_s != session[:pushover_rand].to_s
      raise "rand param #{params[:rand].inspect} != #{session[:pushover_rand].inspect}"
    end

    @user.pushover_user_key = params[:pushover_user_key].to_s
    @user.save!

    flash[:success] = if @user.pushover_user_key.present?
      "Your account is now setup for Pushover notifications."
    else
      "Your account is no longer setup for Pushover notifications."
    end

    redirect_to "/settings"
  end

  def mastodon_authentication
  end

  def mastodon_auth
    app = MastodonApp.find_or_register(params[:mastodon_instance_name])
    if app.persisted?
      session[:mastodon_state] = SecureRandom.hex
      redirect_to app.oauth_auth_url(session[:mastodon_state]), allow_other_host: true
    else
      redirect_to settings_path, flash: {error: app.errors.full_messages.join(" ")}
    end
  end

  def mastodon_callback
    if params[:code].blank? ||
        params[:state].blank? ||
        (params[:state].to_s != session[:mastodon_state].to_s)
      flash[:error] = "Invalid OAuth state"
      return redirect_to settings_path
    end

    app = MastodonApp.find_or_register(params[:instance])
    tok, username = app.token_and_user_from_code(params[:code])
    if tok.present? && username.present?
      @user.mastodon_oauth_token = tok
      @user.mastodon_username = username
      @user.mastodon_instance = params[:instance]
      @user.save!
      flash[:success] = "Linked to Mastodon user @#{username}@#{app.name}."
    else
      flash[:error] = app.errors.full_messages.join(" ")
      return mastodon_disconnect
    end

    redirect_to settings_path
  end

  def mastodon_disconnect
    if (app = MastodonApp.find_by(name: @user.mastodon_instance))
      # revoke_token swallow exceptions about networking errors because indie instances often
      # disappear, so the only thing we can do is delete the record on this side
      app.revoke_token(@user.mastodon_oauth_token)
    end
    @user.mastodon_instance = nil
    @user.mastodon_oauth_token = nil
    @user.mastodon_username = nil
    @user.save!
    # action may be called to tear down a failed auth
    flash[:success] = "Your Mastodon association has been removed." if flash.empty?
    redirect_to settings_path
  end

  def github_auth
    session[:github_state] = SecureRandom.hex
    redirect_to Github.oauth_auth_url(session[:github_state]), allow_other_host: true
  end

  def github_callback
    if session[:github_state].blank? ||
        params[:code].blank? ||
        (params[:state].to_s != session[:github_state].to_s)
      flash[:error] = "Invalid OAuth state"
      return redirect_to settings_path
    end

    session.delete(:github_state)

    tok, username = Github.token_and_user_from_code(params[:code])
    if tok.present? && username.present?
      @user.github_oauth_token = tok
      @user.github_username = username
      @user.save!
      flash[:success] = "Your account has been linked to GitHub user #{username}."
    else
      return github_disconnect
    end

    redirect_to settings_path
  end

  def github_disconnect
    unless Github.revoke_token(@user.github_oauth_token)
      flash[:notice] = "We asked GitHub to revoke our auth token and got an API error, if it still exists you should delete it: https://github.com/settings/applications"
    end
    @user.github_oauth_token = nil
    @user.github_username = nil
    @user.save!
    flash[:success] = "Your GitHub association has been removed."
    redirect_to settings_path
  end

  private

  def user_params
    params.require(:user).permit(
      :username, :homepage, :about, :avatar_source,
      :email_replies, :email_messages, :email_mentions, :inbox_mentions,
      :pushover_replies, :pushover_messages, :pushover_mentions,
      :mailing_list_mode, :show_email, :show_avatars, :show_story_previews,
      :show_submitted_story_threads, :prefers_color_scheme, :prefers_contrast
    )
  end
end
