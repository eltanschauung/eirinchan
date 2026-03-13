defmodule Eirinchan.FormattingPage do
  @moduledoc false

  import Phoenix.Template, only: [render_to_string: 4]

  @left_column_count 52
  @live_sticker_order ~w(
    concern2 milk ninacry smell tempura tenfact grimace wow ahegao nvke headphones cinema
    masaka2 krillin rika ominous kanmarisa mask banjo pout notes elated dogshit mid2 gojo
    angry2 17 yeah vibe thumb waka damn yikes cackle whale glasses fact fact2 thinking bruh
    unyu angry lmao dora boom gasp kys bald meow rofl pensive fact3 pensive2 horse kasawalk
    cum imhungry mindbreak2 scaremu number wemywhale cinema2 bbccry gn ramen2 gokek ramen
    wink mindbreak masaka sip seppuku bruh2 lebron peak peak2 mid dance drool no brain2 poop
    theory lambda shock shock2 upvote youmu pipe happy pog baby kek crawl neutral pray frown
    cath concern gay sign fear brain feelio
  )

  def default_body(sticker_entries \\ []) do
    render_to_string(EirinchanWeb.PageHTML, "formatting_body", "html",
      left_stickers: left_stickers(sticker_entries),
      right_stickers: right_stickers(sticker_entries)
    )
  end

  def normalize_body(html, sticker_entries \\ [])
  def normalize_body(html, sticker_entries) when is_binary(html) do
    trimmed = String.trim(html)

    cond do
      trimmed == "" ->
        default_body(sticker_entries)

      String.contains?(trimmed, "<!doctype html") or String.contains?(trimmed, "<html") ->
        extract_fragment(trimmed, sticker_entries)

      true ->
        trimmed
    end
  end

  def normalize_body(other, _sticker_entries), do: other

  defp left_stickers(sticker_entries) do
    sticker_entries
    |> ordered_stickers()
    |> Enum.take(@left_column_count)
  end

  defp right_stickers(sticker_entries) do
    sticker_entries
    |> ordered_stickers()
    |> Enum.drop(@left_column_count)
  end

  defp ordered_stickers(sticker_entries) do
    order_map =
      @live_sticker_order
      |> Enum.with_index()
      |> Map.new()

    sticker_entries
    |> Enum.sort_by(fn sticker ->
      {Map.get(order_map, sticker_token(sticker), 10_000), sticker_token(sticker)}
    end)
  end

  defp sticker_token(%{token: token}) when is_binary(token), do: token
  defp sticker_token(%{"token" => token}) when is_binary(token), do: token
  defp sticker_token(_sticker), do: ""

  defp extract_fragment(html, sticker_entries) do
    cond do
      capture =
          capture_regex(html, ~r|(<div class="box-wrap(?: faq-page-shell)?(?: formatting-page-shell)?">.*?</div>\s*)<footer|s) ->
        String.trim(capture)

      capture = capture_regex(html, ~r|<body\b[^>]*>(.*)</body>|s) ->
        capture
        |> strip_shell_wrappers()
        |> String.trim()
        |> case do
          "" -> default_body(sticker_entries)
          value -> value
        end

      true ->
        default_body(sticker_entries)
    end
  end

  defp capture_regex(html, regex) do
    case Regex.run(regex, html, capture: :all_but_first) do
      [capture | _rest] -> capture
      _ -> nil
    end
  end

  defp strip_shell_wrappers(body) do
    body
    |> then(&Regex.replace(~r|<div class="boardlist(?: bottom)?">.*?</div>|s, &1, ""))
    |> then(&Regex.replace(~r|<a id="top"></a>|, &1, ""))
    |> then(&Regex.replace(~r|<a id="bottom"></a>|, &1, ""))
    |> then(&Regex.replace(~r|<div class="styles">.*?</div>|s, &1, ""))
    |> then(&Regex.replace(~r|<footer>.*?</footer>|s, &1, ""))
    |> then(&Regex.replace(~r|<script\b[^>]*>.*?</script>|s, &1, ""))
    |> then(&Regex.replace(~r|<style\b[^>]*>.*?</style>|s, &1, ""))
  end
end
