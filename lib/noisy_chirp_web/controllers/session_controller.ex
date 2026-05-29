defmodule ChirpWeb.SessionController do
  @moduledoc "Login + logout HTTP endpoints."
  use ChirpWeb, :controller

  alias ChirpWeb.Auth

  def new(conn, _params) do
    render(conn, :new, page_title: "Login", error: nil)
  end

  def create(conn, %{"password" => password}) when is_binary(password) do
    if Auth.password_correct?(password) do
      Auth.log_in(conn)
    else
      conn
      |> put_flash(:error, "Falsches Passwort.")
      |> render(:new, page_title: "Login", error: "Falsches Passwort.")
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Passwort fehlt.")
    |> render(:new, page_title: "Login", error: "Passwort fehlt.")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Ausgeloggt.")
    |> Auth.log_out()
  end
end
