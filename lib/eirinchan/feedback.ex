defmodule Eirinchan.Feedback do
  @moduledoc """
  Minimal public feedback submission and moderation queue.
  """

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Feedback.{Comment, Entry}
  alias Eirinchan.Repo
  alias Eirinchan.Runtime.Config

  @spec create_feedback(map(), keyword()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def create_feedback(attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    config = Keyword.get(opts, :config, Config.default_config())
    attrs = normalize_attrs(attrs)
    remote_ip = Keyword.get(opts, :remote_ip)

    store_ip =
      Keyword.get(opts, :store_ip, Application.get_env(:eirinchan, :feedback_store_ip, false))

    %Entry{}
    |> Entry.changeset(Map.put(attrs, "ip_subnet", feedback_ip(remote_ip, store_ip)), config)
    |> repo.insert()
  end

  @spec list_feedback(keyword()) :: [Entry.t()]
  def list_feedback(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    repo.all(
      from(feedback in Entry,
        order_by: [asc_nulls_first: feedback.read_at, asc: feedback.inserted_at]
      )
      |> with_comments()
    )
  end

  @spec unread_count(keyword()) :: non_neg_integer()
  def unread_count(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    repo.aggregate(from(feedback in Entry, where: is_nil(feedback.read_at)), :count, :id)
  end

  @spec get_feedback(String.t() | integer(), keyword()) :: Entry.t() | nil
  def get_feedback(feedback_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    case normalize_id(feedback_id) do
      id when is_integer(id) ->
        repo.one(
          from(feedback in Entry, where: feedback.id == ^id)
          |> with_comments()
        )

      nil ->
        nil
    end
  end

  @spec mark_read(String.t() | integer(), keyword()) ::
          {:ok, Entry.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def mark_read(feedback_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    case get_entry(repo, feedback_id) do
      nil ->
        {:error, :not_found}

      entry ->
        entry
        |> Entry.mark_read_changeset(%{
          read_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        })
        |> repo.update()
    end
  end

  @spec delete_feedback(String.t() | integer(), keyword()) ::
          {:ok, Entry.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def delete_feedback(feedback_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    case get_entry(repo, feedback_id) do
      nil -> {:error, :not_found}
      entry -> repo.delete(entry)
    end
  end

  @spec add_comment(String.t() | integer(), map(), keyword()) ::
          {:ok, Comment.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def add_comment(feedback_id, attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    config = Keyword.get(opts, :config, Config.default_config())

    case get_entry(repo, feedback_id) do
      nil ->
        {:error, :not_found}

      entry ->
        %Comment{}
        |> Comment.changeset(
          %{
            "feedback_id" => entry.id,
            "body" => Map.get(normalize_attrs(attrs), "body")
          },
          config
        )
        |> repo.insert()
    end
  end

  @spec import_legacy_file(Path.t(), keyword()) ::
          {:ok, %{imported: non_neg_integer()}} | {:error, :invalid_format | term()}
  def import_legacy_file(path, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    config = Keyword.get(opts, :config, Config.default_config())

    with {:ok, body} <- File.read(path),
         {:ok, entries} <- parse_legacy_feedback(body) do
      repo.transaction(fn ->
        Enum.reduce(entries, 0, fn attrs, imported ->
          {:ok, _entry} =
            %Entry{}
            |> Entry.changeset(attrs, config)
            |> repo.insert()

          imported + 1
        end)
      end)
      |> case do
        {:ok, imported} -> {:ok, %{imported: imported}}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, _reason} = error -> error
    end
  end

  defp with_comments(query) do
    from feedback in query,
      preload: [comments: ^from(comment in Comment, order_by: [asc: comment.inserted_at])]
  end

  defp normalize_attrs(attrs) do
    Enum.into(attrs, %{}, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      pair -> pair
    end)
  end

  defp get_entry(repo, value) do
    case normalize_id(value) do
      id when is_integer(id) -> repo.get(Entry, id)
      nil -> nil
    end
  end

  defp normalize_id(value) when is_integer(value) and value > 0, do: value

  defp normalize_id(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> nil
    end
  end

  defp normalize_id(_value), do: nil

  defp parse_legacy_feedback(body) when is_binary(body) do
    entries =
      body
      |> String.split(~r/^\s*---\s*$/m, trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&parse_legacy_entry/1)

    if entries == [] or Enum.any?(entries, &match?({:error, _}, &1)) do
      {:error, :invalid_format}
    else
      {:ok, Enum.map(entries, fn {:ok, entry} -> entry end)}
    end
  end

  defp parse_legacy_entry(chunk) do
    lines = String.split(chunk, ~r/\R/u, trim: false)

    with {attrs, body_lines} <-
           Enum.split_while(lines, &(not String.match?(&1, ~r/^Body:\s*$/u))),
         [_body_header | rest] <- body_lines do
      parsed =
        Enum.reduce(attrs, %{}, fn line, acc ->
          case String.split(line, ":", parts: 2) do
            [key, value] ->
              Map.put(acc, String.downcase(String.trim(key)), String.trim(value))

            _ ->
              acc
          end
        end)

      {:ok,
       %{
         "name" => parsed["name"],
         "email" => parsed["email"],
         "ip_subnet" => blank_to_default(parsed["ip"], "0.0.0.0"),
         "body" => rest |> Enum.join("\n") |> String.trim()
       }}
    else
      _ -> {:error, :invalid_entry}
    end
  end

  defp blank_to_default(nil, default), do: default

  defp blank_to_default(value, default) do
    case String.trim(value) do
      "" -> default
      trimmed -> trimmed
    end
  end

  defp feedback_ip(_remote_ip, false), do: "0.0.0.0"
  defp feedback_ip(nil, _store_ip), do: "0.0.0.0"

  defp feedback_ip({a, b, _c, _d}, true), do: "#{a}.#{b}.0.0/16"

  defp feedback_ip({a, b, c, _d, _e, _f, _g, _h}, true) do
    encoded =
      [a, b, c]
      |> Enum.map(&(Integer.to_string(&1, 16) |> String.downcase()))
      |> Enum.join(":")

    "#{encoded}::/48"
  end
end
