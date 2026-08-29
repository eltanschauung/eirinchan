defmodule Mix.Tasks.Eirinchan.ImportLivePage do
  use Mix.Task

  @shortdoc "Imports page 1 threads from the live vichan MySQL board into Postgres"

  alias Eirinchan.LiveVichanImport
  alias Eirinchan.PrimaryBoard
  alias Eirinchan.Settings

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [board: :string, limit: :integer, source_root: :string]
      )

    case LiveVichanImport.import_page(
           board:
             Keyword.get_lazy(opts, :board, fn ->
               Settings.effective_instance_config() |> PrimaryBoard.uri()
             end),
           limit: Keyword.get(opts, :limit, 15),
           source_root: Keyword.get(opts, :source_root, "/path/to/vichan")
         ) do
      {:ok, result} ->
        Mix.shell().info(
          "Imported #{result.threads} threads, #{result.replies} replies, #{result.files} files into /#{result.board}/"
        )

      {:error, reason} ->
        Mix.raise("live page import failed: #{inspect(reason)}")
    end
  end
end
