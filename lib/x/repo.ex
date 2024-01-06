defmodule X.Repo do
  use Ecto.Repo,
    otp_app: :x,
    adapter: Ecto.Adapters.Postgres
end
