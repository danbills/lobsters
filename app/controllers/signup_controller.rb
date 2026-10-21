# typed: false

class SignupController < ApplicationController
  include OidcSession

  before_action :require_logged_in_user, :check_new_users, :check_can_invite, only: :invite
  before_action :check_for_read_only_mode, :show_title_h1
  skip_after_action :clear_session_cookie

  def index
    @title = "Create an Account"
    if @user
      flash[:error] = "You are already signed up."
      return redirect_to "/"
    end
    if Rails.application.open_signups?
      redirect_to action: :invited, invitation_code: "open" and return
    end
  end

  def invite
    @title = "Pass Along an Invitation"
  end

  def invited
    @title = "Create an Account"

    if @user
      flash[:error] = "You are already signed up."
      ModNote.tattle_on_invited(@user, params[:invitation_code])
      return redirect_to "/"
    end

    if !Rails.application.open_signups?
      if !(@invitation = Invitation.unused.where(code: params[:invitation_code].to_s).first)
        flash[:error] = "Invalid or expired invitation"
        return redirect_to "/signup"
      end
      # carried through the trip to the identity provider, used by #complete
      session[:invitation_code] = @invitation.code
    end

    @title = "Signup"
    @providers = OidcProvider.all
  end

  # After an OIDC login that didn't match an existing user, OidcController sends them here to
  # pick a username.
  def complete
    @title = "Signup"
    return if !load_pending_signup

    @new_user = User.new(
      username: @pending["suggested_username"],
      email: @pending["email"] || @invitation&.email
    )
  end

  def create
    @title = "Signup"
    return if !load_pending_signup

    @new_user = User.new(user_params)
    @new_user.email = @pending["email"] || @invitation&.email
    @new_user.set_random_password
    @new_user.invited_by_user_id = @invitation&.user_id
    provider = OidcProvider.find(@pending["provider"])

    saved = User.transaction do
      next false if !@new_user.save
      @new_user.identities.create!(
        provider: provider.name,
        issuer: provider.issuer,
        subject: @pending["subject"],
        email: @pending["email"]&.slice(0, 100),
        last_login_at: Time.current
      )
      @invitation&.update!(used_at: Time.current, new_user: @new_user)
      true
    end
    return render action: "complete" if !saved

    start_oidc_session(@new_user, @pending["oidc"])
    flash[:success] = "Welcome to #{Rails.application.name}, #{@new_user.username}!"

    if Rails.application.allow_new_users_to_invite?
      redirect_to signup_invite_path
    else
      redirect_to root_path
    end
  end

  private

  def check_new_users
    if !Rails.application.allow_new_users_to_invite? && @user.is_new?
      redirect_to root_path, flash: {error: "New users cannot send invites"}
    end
  end

  def check_can_invite
    if !@user.can_invite?
      redirect_to root_path, flash: {error: "You can't send invites"}
    end
  end

  # Sets @pending (the IdP identity) and @invitation, or renders why signup can't continue.
  def load_pending_signup
    if @user
      redirect_to "/"
      return false
    end

    if !(@pending = pending_identity)
      flash[:error] = "Your login session expired, please log in again."
      redirect_to login_path
      return false
    end

    if !Rails.application.open_signups?
      @invitation = Invitation.unused.where(code: session[:invitation_code].to_s).first
      if !@invitation
        render :no_invitation, status: :forbidden
        return false
      end
    end

    true
  end

  def user_params
    params.require(:user).permit(:username, :about)
  end
end
