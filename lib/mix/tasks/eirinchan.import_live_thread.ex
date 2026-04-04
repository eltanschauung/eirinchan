defmodule Mix.Tasks.Eirinchan.ImportLiveThread do
  use Mix.Task

  @shortdoc "Imports a single live vichan thread into Postgres"

  alias Eirinchan.LiveVichanImport

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional, _invalid} =
      OptionParser.parse(args,
        strict: [source_root: :string]
      )

    case positional do
      [board_uri, thread_id] ->
        case Integer.parse(thread_id) do
          {parsed_thread_id, ""} ->
            import(board_uri, parsed_thread_id, opts)

          _ ->
            Mix.raise("thread id must be an integer")
        end

      _ ->
        Mix.raise("usage: mix eirinchan.import_live_thread BOARD THREAD_ID [--source_root PATH]")
    end
  end

  defp import(board_uri, thread_id, opts) do
    case LiveVichanImport.import_thread(
           board: board_uri,
           thread_id: thread_id,
           source_root: Keyword.get(opts, :source_root, "/path/to/vichan")
         ) do
      {:ok, result} ->
        Mix.shell().info(
          "Imported /#{result.board}/ live thread #{result.live_thread_id} as No. #{result.imported_public_id} with #{result.replies} replies and #{result.files} files"
        )

      {:error, reason} ->
        Mix.raise("live thread import failed: #{inspect(reason)}")
    end
  end
end
