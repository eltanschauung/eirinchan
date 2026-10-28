defmodule Eirinchan.ListPageDataTest do
  use Eirinchan.DataCase, async: false

  alias Eirinchan.Posts
  alias Eirinchan.Runtime.Config

  test "collects each page once without repeating the first page count query" do
    board = board_fixture()
    thread_fixture(board, %{body: "One"})
    thread_fixture(board, %{body: "Two"})
    config = Config.compose(nil, %{}, %{threads_per_page: 1, max_pages: 10})
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(handler, [:eirinchan, :repo, :query], &__MODULE__.query_event/4, self())

    on_exit(fn -> :telemetry.detach(handler) end)

    assert {:ok, pages} = Posts.list_page_data(board, config: config)
    assert Enum.map(pages, & &1.page) == [1, 2]
    assert Enum.all?(pages, &(length(&1.threads) == 1))
    assert count_events(0) == 2
  end

  test "an empty board keeps its single empty first page" do
    board = board_fixture()
    assert {:ok, [%{page: 1, total_pages: 1, threads: []}]} = Posts.list_page_data(board)
  end

  def query_event(_event, _measurements, metadata, recipient) do
    query = String.downcase(Map.get(metadata, :query, ""))

    if String.contains?(query, "count(") and String.contains?(query, "\"posts\"") do
      send(recipient, :post_count_query)
    end
  end

  defp count_events(count) do
    receive do
      :post_count_query -> count_events(count + 1)
    after
      0 -> count
    end
  end
end
