defmodule ChirpWeb.SessionHTML do
  use ChirpWeb, :html

  def new(assigns) do
    ~H"""
    <main class="min-h-screen bg-base-300 flex items-center justify-center px-4">
      <div class="w-full max-w-sm">
        <div class="text-center mb-8">
          <img src={~p"/images/logo.png"} alt="noisy-chirp" class="w-20 mx-auto mb-3" />
          <h1 class="text-xl font-semibold">noisy-chirp</h1>
        </div>

        <form method="post" action={~p"/login"} class="card bg-base-100 shadow-xl">
          <div class="card-body gap-4">
            <input
              type="hidden"
              name="_csrf_token"
              value={Plug.CSRFProtection.get_csrf_token()}
            />

            <label class="form-control">
              <span class="label-text mb-1">Passwort</span>
              <input
                type="password"
                name="password"
                autofocus
                required
                autocomplete="current-password"
                class="input input-bordered w-full"
              />
            </label>

            <div :if={@error} class="text-sm text-error">{@error}</div>

            <button type="submit" class="btn btn-primary w-full">Login</button>
          </div>
        </form>
      </div>
    </main>
    """
  end
end
