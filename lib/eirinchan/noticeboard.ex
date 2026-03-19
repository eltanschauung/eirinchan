defmodule Eirinchan.Noticeboard do
  @moduledoc """
  Moderator noticeboard entries shown on the dashboard and /manage/noticeboard.
  """

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Noticeboard.Entry
  alias Eirinchan.Repo
  alias EirinchanWeb.HtmlSanitizer

  @default_page_size 50
  @default_dashboard_size 5

  def list_entries(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    page = positive_integer(Keyword.get(opts, :page, 1), 1)
    per_page = positive_integer(Keyword.get(opts, :per_page, @default_page_size), @default_page_size)

    query =
      from entry in Entry,
        order_by: [desc: entry.id],
        offset: ^((page - 1) * per_page),
        limit: ^per_page

    repo.all(query)
  end

  def dashboard_entries(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    limit = positive_integer(Keyword.get(opts, :limit, @default_dashboard_size), @default_dashboard_size)

    repo.all(
      from entry in Entry,
        order_by: [desc: entry.id],
        limit: ^limit
    )
  end

  def count_entries(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    repo.aggregate(Entry, :count, :id)
  end

  def get_entry(id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    repo.get(Entry, id)
  end

  def create_entry(attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    %Entry{}
    |> Entry.changeset(normalize_attrs(attrs))
    |> repo.insert()
  end

  def delete_entry(%Entry{} = entry, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    repo.delete(entry)
  end

  def page_count(total_count, per_page) when is_integer(total_count) and total_count >= 0 do
    per_page = positive_integer(per_page, @default_page_size)
    max(div(total_count + per_page - 1, per_page), 1)
  end

  def formatted_timestamp(%Entry{posted_at: %NaiveDateTime{} = posted_at}) do
    Calendar.strftime(posted_at, "%m/%d/%y (%a) %H:%M:%S")
  end

  def formatted_timestamp(_), do: ""

  def render_body_html(body) when is_binary(body) do
    body
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.replace("\n", "<br>")
    |> HtmlSanitizer.sanitize_fragment()
  end

  def render_body_html(other), do: other |> to_string() |> render_body_html()

  def sanitize_imported_body_html(body_html) when is_binary(body_html) do
    HtmlSanitizer.sanitize_fragment(body_html)
  end

  def sanitize_imported_body_html(other), do: other |> to_string() |> sanitize_imported_body_html()

  def page_size_default, do: @default_page_size
  def dashboard_size_default, do: @default_dashboard_size

  defp normalize_attrs(attrs) do
    attrs
    |> Map.new(fn {key, value} -> {normalize_key(key), value} end)
    |> normalize_body()
    |> Map.update(:subject, nil, &normalize_string/1)
    |> Map.update(:author_name, nil, &normalize_string/1)
  end

  defp normalize_body(%{body_html: _} = attrs), do: attrs

  defp normalize_body(attrs) do
    case Map.fetch(attrs, :body) do
      {:ok, value} ->
        attrs
        |> Map.put(:body_html, render_body_html(value))
        |> Map.delete(:body)

      :error ->
        attrs
    end
  end

  defp normalize_key(key) when is_atom(key), do: key
  defp normalize_key("subject"), do: :subject
  defp normalize_key("body"), do: :body
  defp normalize_key("body_html"), do: :body_html
  defp normalize_key("author_name"), do: :author_name
  defp normalize_key("posted_at"), do: :posted_at
  defp normalize_key("mod_user_id"), do: :mod_user_id
  defp normalize_key(key), do: key

  defp normalize_string(nil), do: nil
  defp normalize_string(value) do
    case value |> to_string() |> String.trim() do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default
end
