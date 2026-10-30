defmodule Eirinchan.FlagsPage do
  @moduledoc false

  import Phoenix.Template, only: [render_to_string: 4]

  alias Eirinchan.LegacyPageBody
  alias Eirinchan.Posts.Flags
  alias EirinchanWeb.PostView

  @gallery_placeholder "{flags.gallery}"
  @controls_placeholder "{flags.controls}"
  @return_link_placeholder "{flags.return_link}"
  @preview_placeholder "{flags.preview}"

  # Upgrade only the shipped legacy body; preserve administrator-written layouts.
  @legacy_default_body """
  {flags.gallery}
  <div id="blotter" class="flag-page-blotter">
    <p1>To rizz your posts, write flag names into the field below, separated by a comma. "country" is a special case that displays your country. If the field is empty, you'll have a US flag.</p1><br /><br />
  </div>
  {flags.controls}
  <br />
  <p1><i>New feature:</i> You can click the flags.</p1>
  {flags.return_link}
  """

  def default_body do
    render_to_string(EirinchanWeb.PageHTML, "flags_body", "html", [])
  end

  def normalize_body(html) do
    normalized = LegacyPageBody.normalize(html, &default_body/0, strip: [:style, :header])

    cond do
      placeholder_body?(normalized) -> default_body()
      body_key(normalized) == body_key(@legacy_default_body) -> default_body()
      dynamic_layout?(normalized) -> normalized
      true -> legacy_article_layout(normalized)
    end
  end

  def expand_dynamic(html, opts \\ []) when is_binary(html) do
    flag_assets = Keyword.get(opts, :flag_assets, [])
    flag_board = Keyword.get(opts, :flag_board)

    preview =
      Keyword.get_lazy(opts, :preview, fn ->
        preview_data(Eirinchan.Runtime.Config.default_config(), %{}, "country")
      end)

    html
    |> ensure_preview_slot()
    |> String.replace(
      @gallery_placeholder,
      render_to_string(EirinchanWeb.PageHTML, "flag_gallery", "html", flag_assets: flag_assets)
    )
    |> String.replace(
      @controls_placeholder,
      render_to_string(EirinchanWeb.PageHTML, "flag_controls", "html", flag_value: preview.value)
    )
    |> String.replace(
      @preview_placeholder,
      render_to_string(EirinchanWeb.PageHTML, "flag_preview", "html", preview: preview)
    )
    |> String.replace(
      @return_link_placeholder,
      render_to_string(EirinchanWeb.PageHTML, "flag_return_link", "html", flag_board: flag_board)
    )
  end

  def preview_data(config, request, value) do
    # Resolve country/fallback with the posting pipeline. Only public flag
    # presentation metadata goes to the client, never the underlying address.
    selected_config = %{config | country_flags: false, user_flag: true}

    render = fn attrs ->
      {:ok, normalized} = Flags.normalize(attrs, selected_config, request)
      preview_flags(normalized_post(normalized), config)
    end

    {:ok, automatic} = Flags.normalize(%{}, %{config | user_flag: false}, request)
    base = preview_flags(normalized_post(automatic), config)
    fallback = render.(%{"user_flag" => ""})
    country = render.(%{"user_flag" => "country"})

    catalog =
      Map.new(config.user_flags, fn {code, label} ->
        key = code |> to_string() |> String.trim() |> String.downcase()
        {key, preview_flags(%{flag_codes: [key], flag_alts: [to_string(label)]}, config)}
      end)
      |> Map.put("country", country)
      |> Map.put(to_string(config.country_flag_fallback.code) |> String.downcase(), fallback)

    initial =
      case Flags.normalize(%{"user_flag" => value}, selected_config, request) do
        {:ok, attrs} -> base ++ preview_flags(normalized_post(attrs), config)
        _ -> base
      end

    %{
      flags: catalog,
      base: base,
      fallback: fallback,
      multiple: config.multiple_flags,
      style: PostView.flag_style(config),
      initial: initial,
      value: value
    }
  end

  defp normalized_post(attrs),
    do: %{
      flag_codes: Map.get(attrs, "flag_codes", []),
      flag_alts: Map.get(attrs, "flag_alts", [])
    }

  defp preview_flags(post, config),
    do: post |> PostView.post_flags(config) |> Enum.map(&Map.take(&1, [:src, :alt]))

  # Older custom layouts may have gallery/controls slots but no preview slot.
  # Add the new capability without replacing any administrator-authored copy.
  defp ensure_preview_slot(html) do
    cond do
      String.contains?(html, @preview_placeholder) ->
        html

      String.contains?(html, @controls_placeholder) ->
        String.replace(
          html,
          @controls_placeholder,
          @controls_placeholder <> "\n" <> @preview_placeholder
        )

      true ->
        html <> "\n" <> @preview_placeholder
    end
  end

  defp body_key(body) do
    body
    |> String.replace(~r/<br\s*\/?>/i, "<br>")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp dynamic_layout?(html) when is_binary(html) do
    Enum.any?(
      [
        @gallery_placeholder,
        @controls_placeholder,
        @return_link_placeholder,
        @preview_placeholder
      ],
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
