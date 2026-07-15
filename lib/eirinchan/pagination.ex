defmodule Eirinchan.Pagination do
  @moduledoc """
  Shared, integer-only pagination helpers for public and moderation pages.
  """

  @default_window_threshold 9
  @default_window_radius 2

  @spec page_size(term(), pos_integer(), keyword()) :: pos_integer()
  def page_size(value, default, opts \\ []) when is_integer(default) and default > 0 do
    value = positive_integer(value, default)

    case Keyword.get(opts, :max) do
      max when is_integer(max) and max > 0 -> min(value, max)
      _ -> value
    end
  end

  @spec page_count(non_neg_integer(), pos_integer(), keyword()) :: pos_integer()
  def page_count(total_entries, page_size, opts \\ [])
      when is_integer(total_entries) and total_entries >= 0 and is_integer(page_size) and
             page_size > 0 do
    count = max(div(total_entries + page_size - 1, page_size), 1)

    case Keyword.get(opts, :max_pages) do
      max_pages when is_integer(max_pages) and max_pages > 0 -> min(count, max_pages)
      _ -> count
    end
  end

  @spec paginate(list(), pos_integer(), pos_integer()) :: {:ok, map()} | {:error, :not_found}
  def paginate(entries, page, page_size)
      when is_list(entries) and is_integer(page) and is_integer(page_size) and page_size > 0 do
    total_entries = length(entries)
    total_pages = page_count(total_entries, page_size)

    if page < 1 or page > total_pages do
      {:error, :not_found}
    else
      {:ok,
       %{
         entries: Enum.slice(entries, (page - 1) * page_size, page_size),
         page: page,
         page_size: page_size,
         total_entries: total_entries,
         total_pages: total_pages
       }}
    end
  end

  @spec window([map()], pos_integer(), keyword()) :: [map() | :ellipsis]
  def window(pages, current_page, opts \\ []) when is_list(pages) do
    threshold = page_size(Keyword.get(opts, :threshold), @default_window_threshold)
    radius = page_size(Keyword.get(opts, :radius), @default_window_radius)

    if length(pages) <= threshold do
      pages
    else
      first_page = pages |> List.first() |> page_number()
      last_page = pages |> List.last() |> page_number()

      pages
      |> Enum.filter(fn page ->
        number = page_number(page)
        number in [first_page, last_page] or abs(number - current_page) <= radius
      end)
      |> insert_ellipses()
    end
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value

  defp positive_integer(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp positive_integer(_value, default), do: default

  defp page_number(%{num: number}) when is_integer(number), do: number

  defp insert_ellipses(pages) do
    pages
    |> Enum.reduce([], fn page, acc ->
      case acc do
        [] ->
          [page]

        [previous | _] ->
          if page_number(page) - page_number(previous) > 1 do
            [page, :ellipsis | acc]
          else
            [page | acc]
          end
      end
    end)
    |> Enum.reverse()
  end
end
