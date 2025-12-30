defmodule Play.Repo do
  use Ecto.Repo,
    otp_app: :play,
    adapter: Ecto.Adapters.Postgres
end
