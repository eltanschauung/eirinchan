defmodule EirinchanWeb.HtmlSanitizer do
  @moduledoc false

  @strip_tags ~w(script iframe object embed base meta)
  @tag_pattern Enum.join(@strip_tags, "|")

  def sanitize_fragment(nil), do: ""

  def sanitize_fragment(html) when is_binary(html) do
    html
    |> strip_dangerous_tags()
    |> strip_event_attributes()
    |> strip_srcdoc_attributes()
    |> neutralize_script_urls()
  end

  def sanitize_fragment(other), do: sanitize_fragment(to_string(other))

  defp strip_dangerous_tags(html) do
    Regex.replace(
      ~r/<\s*(#{@tag_pattern})\b[^>]*>.*?<\s*\/\s*\1\s*>|<\s*(#{@tag_pattern})\b[^>]*\/?\s*>/is,
      html,
      ""
    )
  end

  defp strip_event_attributes(html) do
    html
    |> then(&Regex.replace(~r/\s+on[a-z0-9_-]+\s*=\s*"[^"]*"/i, &1, ""))
    |> then(&Regex.replace(~r/\s+on[a-z0-9_-]+\s*=\s*'[^']*'/i, &1, ""))
    |> then(&Regex.replace(~r/\s+on[a-z0-9_-]+\s*=\s*[^\s>]+/i, &1, ""))
  end

  defp strip_srcdoc_attributes(html) do
    html
    |> then(&Regex.replace(~r/\s+srcdoc\s*=\s*"[^"]*"/i, &1, ""))
    |> then(&Regex.replace(~r/\s+srcdoc\s*=\s*'[^']*'/i, &1, ""))
    |> then(&Regex.replace(~r/\s+srcdoc\s*=\s*[^\s>]+/i, &1, ""))
  end

  defp neutralize_script_urls(html) do
    Regex.replace(
      ~r/\b(href|src|action|formaction|xlink:href)\s*=\s*(['"])\s*(?:javascript|vbscript)\s*:[^'"]*\2/i,
      html,
      "\\1=\\2#\\2"
    )
  end
end
