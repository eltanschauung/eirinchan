defmodule Eirinchan.FlagsPage do
  @moduledoc false

  import Phoenix.Template, only: [render_to_string: 4]

  alias Eirinchan.LegacyPageBody

  @gallery_placeholder "{flags.gallery}"
  @controls_placeholder "{flags.controls}"
  @return_link_placeholder "{flags.return_link}"

  def default_body do
    render_to_string(EirinchanWeb.PageHTML, "flags_body", "html", [])
  end

  def normalize_body(html) do
    normalized = LegacyPageBody.normalize(html, &default_body/0, strip: [:style, :header])

    cond do
      placeholder_body?(normalized) -> default_body()
      dynamic_layout?(normalized) -> normalized
      true -> legacy_article_layout(normalized)
    end
  end

  def expand_dynamic(html, opts \\ []) when is_binary(html) do
    flag_assets = Keyword.get(opts, :flag_assets, [])
    flag_board = Keyword.get(opts, :flag_board)

    html
    |> String.replace(
      @gallery_placeholder,
      render_to_string(EirinchanWeb.PageHTML, "flag_gallery", "html", flag_assets: flag_assets)
    )
    |> String.replace(
      @controls_placeholder,
      render_to_string(EirinchanWeb.PageHTML, "flag_controls", "html", [])
    )
    |> String.replace(
      @return_link_placeholder,
      render_to_string(EirinchanWeb.PageHTML, "flag_return_link", "html", flag_board: flag_board)
    )
  end

  defp dynamic_layout?(html) when is_binary(html) do
    Enum.any?(
      [@gallery_placeholder, @controls_placeholder, @return_link_placeholder],
      &String.contains?(html, &1)
    )
  end

  defp placeholder_body?(value) when is_binary(value) do
    String.trim(value) in ["", "Flags", "Custom flags", "Pick custom flags for your posts."]
  end

  defp legacy_article_layout(html) do
    """
    <article class="flag-page-copy">
    #{html}
    </article>
    #{default_body()}
    """
    |> String.trim()
  end
end
