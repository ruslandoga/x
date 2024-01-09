defmodule X do
  @moduledoc """
  X keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  def truncate_imported_tables do
    Task.async(fn ->
      {:ok, ch} = X.Ch.Repo.config() |> Keyword.replace!(:pool_size, 1) |> Ch.start_link()

      Ch.query!(ch, "show tables").rows
      |> Enum.map(fn [table] -> table end)
      |> Enum.filter(fn table -> String.starts_with?(table, "imported_") end)
      |> Enum.each(&Ch.query!(ch, "truncate {table:Identifier}", %{"table" => &1}))
    end)
    |> Task.await()
  end
end
