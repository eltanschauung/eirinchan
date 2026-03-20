defmodule Eirinchan.Posts.UploadPreparation do
  @moduledoc false

  alias Eirinchan.Uploads

  def prepare_uploads(attrs, config, _opts \\ []) do
    prepare_file_uploads(attrs, config)
    |> case do
      {:ok, prepared_attrs} ->
        {:ok, prepared_attrs}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def cleanup_uploads(attrs) when is_map(attrs) do
    attrs
    |> Map.get("__upload_entries__", [])
    |> Enum.each(fn
      %{metadata: metadata} -> Uploads.cleanup_prepared(metadata)
      _ -> :ok
    end)

    :ok
  end

  def cleanup_uploads(_attrs), do: :ok

  def normalize_embed(attrs, %{enable_embedding: false}) do
    {:ok, Map.put(attrs, "embed", nil)}
  end

  def normalize_embed(attrs, config) do
    case trim_to_nil(Map.get(attrs, "embed")) do
      nil ->
        {:ok, Map.put(attrs, "embed", nil)}

      embed ->
        if valid_embed?(embed, config) do
          {:ok, Map.put(attrs, "embed", embed)}
        else
          {:error, :invalid_embed}
        end
    end
  end

  defp prepare_file_uploads(attrs, config) do
    op? = is_nil(trim_to_nil(Map.get(attrs, "thread")))

    with {:ok, attrs, uploads} <- maybe_add_remote_upload(attrs, config) do
      case Enum.reduce_while(uploads, {:ok, []}, fn upload, {:ok, entries} ->
             case Uploads.prepare(upload, config, op?: op?) do
               {:ok, metadata} ->
                 {:cont, {:ok, [%{upload: upload, metadata: metadata} | entries]}}

               {:error, reason} ->
                 Enum.each(entries, fn entry -> Uploads.cleanup_prepared(entry.metadata) end)
                 {:halt, {:error, reason}}
             end
           end) do
        {:ok, []} ->
          {:ok, attrs |> Map.put("file", nil) |> Map.put("__upload_entries__", [])}

        {:ok, entries} ->
          entries = Enum.reverse(entries)
          [primary | _] = entries

          {:ok,
           attrs
           |> Map.put("file", primary.upload)
           |> Map.put("__upload_metadata__", primary.metadata)
           |> Map.put("__upload_entries__", maybe_apply_spoiler(attrs, entries))}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp valid_embed?(embed, config) do
    Enum.any?(List.wrap(Map.get(config, :embedding, [])), fn rule ->
      case normalize_embedding_rule(rule) do
        {:ok, regex, _html} -> Regex.match?(regex, embed)
        :error -> false
      end
    end)
  end

  defp normalize_embedding_rule([pattern, html]) when is_binary(html),
    do: compile_embedding_regex(pattern, html)

  defp normalize_embedding_rule(%{"pattern" => pattern, "html" => html}),
    do: compile_embedding_regex(pattern, html)

  defp normalize_embedding_rule(%{pattern: pattern, html: html}),
    do: compile_embedding_regex(pattern, html)

  defp normalize_embedding_rule(_rule), do: :error

  defp compile_embedding_regex(%Regex{} = regex, html), do: {:ok, regex, html}

  defp compile_embedding_regex(pattern, html) when is_binary(pattern) and is_binary(html) do
    case parse_regex(pattern) do
      {:ok, regex} -> {:ok, regex, html}
      :error -> :error
    end
  end

  defp compile_embedding_regex(_pattern, _html), do: :error

  defp parse_regex("/" <> rest) do
    with [source, modifiers] <-
           Regex.run(~r{\A/(.*)/([a-z]*)\z}s, "/" <> rest, capture: :all_but_first),
         options <- regex_options(modifiers),
         {:ok, regex} <- Regex.compile(source, options) do
      {:ok, regex}
    else
      _ -> :error
    end
  end

  defp parse_regex(_pattern), do: :error

  defp regex_options(modifiers) do
    modifiers
    |> String.graphemes()
    |> Enum.reduce("", fn
      "i", acc -> acc <> "i"
      "m", acc -> acc <> "m"
      "s", acc -> acc <> "s"
      "u", acc -> acc <> "u"
      _, acc -> acc
    end)
  end

  defp collect_uploads(attrs) do
    numbered_uploads =
      attrs
      |> Enum.filter(fn
        {<<"file", rest::binary>>, %Plug.Upload{}} when rest != "" ->
          String.match?(rest, ~r/^\d+$/)

        _ ->
          false
      end)
      |> Enum.sort_by(fn {key, _upload} ->
        key
        |> String.replace_prefix("file", "")
        |> String.to_integer()
      end)
      |> Enum.map(&elem(&1, 1))

    [
      Map.get(attrs, "file"),
      Map.get(attrs, "files"),
      Map.get(attrs, "files[]") | numbered_uploads
    ]
    |> Enum.flat_map(fn
      nil ->
        []

      %Plug.Upload{} = upload ->
        [upload]

      uploads when is_list(uploads) ->
        Enum.filter(uploads, &match?(%Plug.Upload{}, &1))

      uploads when is_map(uploads) ->
        uploads |> Map.values() |> Enum.filter(&match?(%Plug.Upload{}, &1))

      _ ->
        []
    end)
  end

  defp maybe_add_remote_upload(attrs, config) do
    uploads = collect_uploads(attrs)

    cond do
      uploads != [] ->
        {:ok, attrs, uploads}

      not config.upload_by_url_enabled ->
        {:ok, attrs, uploads}

      true ->
        case trim_to_nil(Map.get(attrs, "file_url") || Map.get(attrs, "url")) do
          nil ->
            {:ok, attrs, uploads}

          remote_url ->
            case Uploads.fetch_remote_upload(remote_url, config) do
              {:ok, upload} -> {:ok, Map.put(attrs, "file", upload), [upload]}
              {:error, reason} -> {:error, reason}
            end
        end
    end
  end

  defp maybe_apply_spoiler(attrs, entries) do
    spoiler? = truthy?(Map.get(attrs, "spoiler"))

    Enum.map(entries, fn entry ->
      %{entry | metadata: Map.put(entry.metadata, :spoiler, spoiler?)}
    end)
  end

  defp truthy?(value) when value in [true, "true", "1", 1, "on"], do: true
  defp truthy?(_value), do: false

  defp trim_to_nil(nil), do: nil

  defp trim_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
