defmodule Eirinchan.PaginationTest do
  use ExUnit.Case, async: true

  alias Eirinchan.Pagination

  test "normalizes configured page sizes and caps them when requested" do
    assert Pagination.page_size("25", 10) == 25
    assert Pagination.page_size(0, 10) == 10
    assert Pagination.page_size("invalid", 10) == 10
    assert Pagination.page_size(500, 10, max: 100) == 100
  end

  test "calculates page counts with integer arithmetic and an optional cap" do
    assert Pagination.page_count(0, 10) == 1
    assert Pagination.page_count(21, 10) == 3
    assert Pagination.page_count(101, 10, max_pages: 5) == 5
  end

  test "paginates lists and rejects pages outside the result set" do
    assert {:ok, page} = Pagination.paginate(Enum.to_list(1..12), 2, 5)
    assert page.entries == [6, 7, 8, 9, 10]
    assert page.total_entries == 12
    assert page.total_pages == 3
    assert {:error, :not_found} = Pagination.paginate(Enum.to_list(1..12), 4, 5)
  end

  test "compacts large page ranges while retaining nearby and boundary pages" do
    pages = Enum.map(1..20, &%{num: &1, link: "/#{&1}"})

    assert Enum.map(Pagination.window(pages, 10), fn
             :ellipsis -> :ellipsis
             page -> page.num
           end) == [1, :ellipsis, 8, 9, 10, 11, 12, :ellipsis, 20]
  end
end
