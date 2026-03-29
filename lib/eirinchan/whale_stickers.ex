defmodule Eirinchan.WhaleStickers do
  @moduledoc """
  Runtime helpers for the vichan-style whale sticker replacement system.
  """

  alias Eirinchan.Settings
  alias Eirinchan.WhaleStickers.Defaults

  def default_entries, do: Defaults.entries()

  def entries(config_or_settings \\ %{})

  def entries(%{whalestickers: entries}) when is_list(entries),
    do: normalize_entries(entries, Defaults.entries())

  def entries(settings) when is_map(settings) do
    settings
    |> Map.get(:whalestickers, Defaults.entries())
    |> normalize_entries(Defaults.entries())
  end

  def entries(_), do: Defaults.entries()

  def encode_for_edit do
    Settings.current_instance_config()
    |> entries()
    |> Jason.encode!(pretty: true)
  end

  def update(raw_json) when is_binary(raw_json) do
    with {:ok, decoded} <- Jason.decode(raw_json),
         true <- is_list(decoded),
         normalized <- normalize_entries(decoded, nil),
         false <- is_nil(normalized),
         config <- Map.put(Settings.current_instance_config(), :whalestickers, normalized),
         :ok <- Settings.persist_instance_config(config) do
      {:ok, normalized}
    else
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_json}
      true -> {:error, :invalid_json}
      false -> {:error, :invalid_json}
      nil -> {:error, :invalid_json}
      {:error, _} = error -> error
      _ -> {:error, :invalid_json}
    end
  end

  def replace_line(line, config) when is_binary(line) do
    case sticker_match(line, entries(config)) do
      nil -> line
      %{entry: entry, rest: rest} -> sticker_html(entry, rest)
    end
  end

  def replace_line(line, _config), do: line

  def contains_sticker?(body, config) when is_binary(body) do
    body
    |> String.split("\n")
    |> Enum.any?(fn line -> sticker_match(line, entries(config)) != nil end)
  end

  def contains_sticker?(_body, _config), do: false

  defp normalize_entries(entries, fallback) when is_list(entries) do
    normalized =
      entries
      |> Enum.map(&normalize_entry/1)
      |> Enum.reject(&is_nil/1)

    cond do
      normalized != [] -> normalized
      is_list(fallback) -> fallback
      true -> nil
    end
  end

  defp normalize_entry(%{"token" => token, "file" => file} = entry),
    do:
      normalize_entry(%{
        token: token,
        file: file,
        title: entry["title"],
        append_break: entry["append_break"]
      })

  defp normalize_entry(%{token: token, file: file} = entry) do
    token = token |> to_string() |> String.trim()
    file = file |> to_string() |> String.trim() |> Path.basename()

    if token == "" or file == "" do
      nil
    else
      %{
        token: token,
        file: file,
        title: entry |> Map.get(:title, token) |> to_string() |> String.trim(),
        append_break: Map.get(entry, :append_break, false) in [true, "true", 1, "1"]
      }
    end
  end

  defp normalize_entry(_), do: nil

  defp sticker_match(line, entries) do
    Enum.find_value(entries, fn entry ->
      regex = ~r/^\s*:#{Regex.escape(entry.token)}:(.*)$/s

      case Regex.run(regex, line) do
        [_, rest] -> %{entry: entry, rest: rest}
        _ -> nil
      end
    end)
  end

  defp sticker_html(entry, rest) do
    suffix = if entry.append_break, do: "<br>", else: ""

    ~s(<img src="/whalestickers/#{html_escape(entry.file)}" title=":#{html_escape(entry.title)}:">#{rest}#{suffix})
  end

  defp html_escape(value), do: Phoenix.HTML.html_escape(value) |> Phoenix.HTML.safe_to_string()
end
