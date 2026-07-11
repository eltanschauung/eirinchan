defmodule Eirinchan.FlagsPage do
  @moduledoc false

  alias Eirinchan.LegacyPageBody

  def default_body do
    """
    Pick custom flags for your posts.
    """
    |> String.trim()
  end

  def normalize_body(html) do
    LegacyPageBody.normalize(html, &default_body/0, strip: [:style, :header])
  end

  def article_html(html) when is_binary(html) do
    normalized = normalize_body(html)

    if placeholder_body?(normalized), do: nil, else: blank_to_nil(normalized)
  end

  def article_html(_html), do: nil

  def description_html do
    """
    <p1>To rizz your posts, write flag names into the field below, separated by a comma. "country" is a special case that displays your country. If the field is empty, you'll have a US flag.</p1><br><br>
    """
    |> String.trim()
  end

  def footer_html do
    """
    <p1><i>New feature:</i> You can click the flags.</p1>
    """
    |> String.trim()
  end

  defp placeholder_body?(value) when is_binary(value) do
    String.trim(value) in ["", "Flags", "Custom flags", "Pick custom flags for your posts."]
  end

  defp blank_to_nil(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end
end
