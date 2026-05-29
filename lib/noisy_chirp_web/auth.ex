defmodule ChirpWeb.Auth do
  @moduledoc """
  Single-user, password-based session auth.

  The expected password lives in `:noisy_chirp, :admin_password` (sourced
  from the `ADMIN_PASSWORD` env in prod). If the config is missing or the
  empty string, the admin area is locked — there's no way to log in.
  """
  import Plug.Conn
  import Phoenix.Controller
  use ChirpWeb, :verified_routes

  @session_key :user_authenticated

  # ---- Controller plug ----

  @doc "Plug — short-circuits to /login when no authenticated session."
  def require_authenticated_user(conn, _opts) do
    if get_session(conn, @session_key) do
      conn
    else
      conn
      |> put_flash(:error, "Bitte einloggen.")
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end

  # ---- LiveView ----

  @doc """
  `on_mount` callback for LiveViews behind the admin pipeline. The
  LiveView socket has access to the session, so we re-check there.
  """
  def on_mount(:ensure_authenticated, _params, session, socket) do
    if session["user_authenticated"] do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/login")}
    end
  end

  # ---- Session ops (called from SessionController) ----

  def log_in(conn) do
    conn
    |> renew_session()
    |> put_session(@session_key, true)
    |> redirect(to: ~p"/admin")
  end

  def log_out(conn) do
    conn
    |> renew_session()
    |> redirect(to: ~p"/")
  end

  @doc """
  Verifies the submitted password against the configured one in constant
  time. Returns `true` only when both are set and equal.
  """
  def password_correct?(submitted) when is_binary(submitted) do
    case Application.get_env(:noisy_chirp, :admin_password) do
      pw when is_binary(pw) and byte_size(pw) > 0 ->
        Plug.Crypto.secure_compare(pw, submitted)

      _ ->
        false
    end
  end

  def password_correct?(_), do: false

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
