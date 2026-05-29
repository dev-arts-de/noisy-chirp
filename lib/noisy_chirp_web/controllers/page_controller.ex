defmodule ChirpWeb.PageController do
  @moduledoc "Static-ish landing page — just the logo."
  use ChirpWeb, :controller

  def landing(conn, _params) do
    conn
    |> assign(:page_title, "noisy-chirp")
    |> render(:landing)
  end
end
