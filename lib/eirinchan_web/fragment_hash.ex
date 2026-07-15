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
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end

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
