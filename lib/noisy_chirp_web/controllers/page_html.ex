defmodule ChirpWeb.PageHTML do
  use ChirpWeb, :html

  def landing(assigns) do
    ~H"""
    <main class="min-h-screen flex flex-col items-center justify-center bg-base-200 px-4">
      <a href={~p"/login"} class="block group">
        <img
          src={~p"/images/logo.png"}
          alt="noisy-chirp"
          class="w-48 sm:w-56 transition-transform group-hover:scale-105"
        />
      </a>
    </main>
    """
  end
end
