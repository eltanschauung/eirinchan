defmodule Eirinchan.Boards do
  @moduledoc """
  Board context loading modeled after vichan's `openBoard`.
  """

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Boards.{Board, EctoStore}
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.PrimaryBoard
  alias Eirinchan.Repo
  alias Eirinchan.Runtime
  alias Eirinchan.Runtime.{Config, RequestContext}
  alias Eirinchan.Settings

  @spec list_boards(keyword()) :: [BoardRecord.t()]
  def list_boards(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    repo.all(from board in BoardRecord, order_by: [asc: board.uri])
  end

  @spec get_board!(term(), keyword()) :: BoardRecord.t()
  def get_board!(id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    repo.get!(BoardRecord, id)
  end

  @spec get_board_by_uri(String.t(), keyword()) :: BoardRecord.t() | nil
  def get_board_by_uri(uri, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    repo.get_by(BoardRecord, uri: String.trim(uri, "/"))
  end

  @spec get_board_by_uri!(String.t(), keyword()) :: BoardRecord.t()
  def get_board_by_uri!(uri, opts \\ []) do
    case get_board_by_uri(uri, opts) do
      nil -> raise Ecto.NoResultsError, queryable: BoardRecord
      board -> board
    end
  end

  @spec create_board(map(), keyword()) :: {:ok, BoardRecord.t()} | {:error, Ecto.Changeset.t()}
  def create_board(attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    %BoardRecord{}
    |> BoardRecord.changeset(attrs)
    |> repo.insert()
  end

  @spec update_board(BoardRecord.t(), map(), keyword()) ::
          {:ok, BoardRecord.t()} | {:error, Ecto.Changeset.t()}
  def update_board(%BoardRecord{} = board, attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    board
    |> BoardRecord.changeset(attrs)
    |> repo.update()
  end

  @spec delete_board(BoardRecord.t(), keyword()) ::
          {:ok, BoardRecord.t()} | {:error, Ecto.Changeset.t() | :primary_board}
  def delete_board(%BoardRecord{} = board, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    instance_config =
      Keyword.get_lazy(opts, :instance_config, &Settings.effective_instance_config/0)

    if board.uri == PrimaryBoard.uri(instance_config) do
      {:error, :primary_board}
    else
      repo.delete(board)
    end
  end

  @spec change_board(BoardRecord.t(), map()) :: Ecto.Changeset.t()
  def change_board(%BoardRecord{} = board, attrs \\ %{}) do
    BoardRecord.changeset(board, attrs)
  end

  @spec open_board(String.t(), keyword()) :: {:ok, RequestContext.t()} | {:error, :not_found}
  def open_board(uri, opts \\ []) do
    context = Keyword.get_lazy(opts, :context, fn -> Runtime.bootstrap(opts) end)

    case context do
      %RequestContext{board: %Board{uri: ^uri}} ->
        {:ok, context}

      %RequestContext{} ->
        do_open_board(uri, context, opts)
    end
  end

  defp do_open_board(uri, %RequestContext{} = context, opts) do
    {store, store_opts} = Keyword.get(opts, :board_store, {EctoStore, []})

    with {:ok, board} <- store.fetch_by_uri(uri, store_opts) do
      board = Board.with_runtime_paths(board, context.config)

      effective_config =
        Config.compose(
          Keyword.get(opts, :defaults),
          Keyword.get(opts, :instance_overrides, Settings.current_instance_config()),
          board.config_overrides,
          board: board,
          request_host: Keyword.get(opts, :request_host)
        )

      {:ok, %RequestContext{context | board: board, config: effective_config}}
    end
  end
end
