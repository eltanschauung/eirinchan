defmodule EirinchanWeb.FragmentHash do
  @moduledoc false

  @csrf_input_pattern ~r/<input[^>]*name="_csrf_token"[^>]*>/i

  def md5(view, template, assigns, opts \\ []) do
    cache_key = Keyword.get(opts, :cache_key)

    if is_nil(cache_key) do
      render_md5(view, template, assigns)
    else
      EirinchanWeb.FragmentCache.fetch_or_store(cache_key, fn ->
        render_md5(view, template, assigns)
      end)
    end
  end

  def term_digest(value) do
    value
    |> stable_term()
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end

  # OTP 28+ stores compiled regular expressions as VM references. Hash the
  # expression's meaning, so compiling the same config on the next request
  # cannot invalidate otherwise unchanged fragments.
  defp stable_term(%Regex{} = regex), do: {Regex, Regex.source(regex), Regex.opts(regex)}

  defp stable_term(value) when is_map(value),
    do: Map.new(Map.to_list(value), fn {key, item} -> {stable_term(key), stable_term(item)} end)

  defp stable_term(value) when is_list(value), do: Enum.map(value, &stable_term/1)

  defp stable_term(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.map(&stable_term/1) |> List.to_tuple()

  defp stable_term(value), do: value

  defp render_md5(view, template, assigns) do
    html =
      Phoenix.Template.render_to_string(
        view,
        Atom.to_string(template),
        "html",
        Keyword.put(assigns, :fragment_md5, nil)
      )
      |> normalize()

    :md5
    |> :crypto.hash(html)
    |> Base.encode16(case: :lower)
  end

  defp normalize(html) do
    Regex.replace(@csrf_input_pattern, html, "")
  end
end
