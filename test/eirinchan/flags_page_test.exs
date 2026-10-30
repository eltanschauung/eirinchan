defmodule Eirinchan.FlagsPageTest do
  use ExUnit.Case, async: true

  alias Eirinchan.FlagsPage
  alias Eirinchan.Runtime.Config

  defp config do
    %{
      Config.default_config()
      | user_flag: true,
        multiple_flags: true,
        uri_flags: "flags/compiled/%s.png",
        flag_style: "width:20px;height:14px;",
        user_flags: %{"meiling" => "Meiling", "tenshi" => "Tenshi"}
    }
  end

  test "preview resolves country, fallback, labels and ordered duplicates through posting rules" do
    preview =
      FlagsPage.preview_data(
        config(),
        %{country: %{code: "ca", name: "Canada"}},
        "country,meiling,meiling"
      )

    assert preview.base == []
    assert preview.flags["country"] == [%{src: "/flags/compiled/ca.png", alt: "Canada"}]
    assert preview.fallback == [%{src: "/flags/compiled/us.png", alt: "United States"}]
    assert Enum.map(preview.initial, & &1.alt) == ["Canada", "Meiling", "Meiling"]
    assert preview.style == "width:20px;height:14px;"
    assert preview.flags["meiling"] |> hd() |> Map.keys() |> Enum.sort() == [:alt, :src]
  end

  test "empty fields use fallback while automatic country flags retain their posting order" do
    config = %{config() | country_flags: true}
    preview = FlagsPage.preview_data(config, %{country: %{code: "ca", name: "Canada"}}, "")
    assert Enum.map(preview.initial, & &1.alt) == ["Canada", "United States"]
    assert Enum.map(preview.base, & &1.alt) == ["Canada"]

    hidden = FlagsPage.preview_data(%{config | display_flags: false}, %{}, "country")
    assert hidden.initial == []
    assert Enum.all?(hidden.flags, fn {_key, flags} -> flags == [] end)
  end

  test "upgrades only the previous shipped default and preserves custom administrator bodies" do
    old = """
    {flags.gallery}
    <div id="blotter" class="flag-page-blotter">
      <p1>To rizz your posts, write flag names into the field below, separated by a comma. "country" is a special case that displays your country. If the field is empty, you'll have a US flag.</p1><br><br>
    </div>
    {flags.controls}
    <br>
    <p1><i>New feature:</i> You can click the flags.</p1>
    {flags.return_link}
    """

    updated = FlagsPage.normalize_body(old)
    assert updated == FlagsPage.default_body()
    assert updated =~ "{flags.preview}"
    refute updated =~ "New feature:"

    custom = "<p>Administrator instructions.</p>{flags.gallery}{flags.controls}{flags.preview}"
    assert FlagsPage.normalize_body(custom) == custom
  end

  test "existing custom layouts receive a working preview without losing their own copy" do
    body = "<p>Custom instructions.</p>{flags.gallery}{flags.controls}{flags.return_link}"

    html =
      FlagsPage.expand_dynamic(body, preview: FlagsPage.preview_data(config(), %{}, "meiling"))

    document = Floki.parse_document!(html)
    assert html =~ "Custom instructions."
    assert length(Floki.find(document, "[data-flag-preview]")) == 1
    assert Floki.find(document, "#exampleBox + [data-flag-preview]") != []
    assert Floki.attribute(document, "#user_flag", "value") == ["meiling"]
  end
end
