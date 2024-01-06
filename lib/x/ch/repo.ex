defmodule X.Ch.Repo do
  use Ecto.Repo, otp_app: :x, adapter: Ecto.Adapters.ClickHouse
end
