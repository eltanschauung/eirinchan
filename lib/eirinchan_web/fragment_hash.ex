defmodule EirinchanWeb.FragmentHash do
  @moduledoc false

  @csrf_input_pattern ~r/<input[^>]*name="_csrf_token"[^>]*>/i

  def md5(view, template, assigns) do
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
