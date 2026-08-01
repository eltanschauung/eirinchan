defmodule EirinchanWeb.RecentStylesheetTest do
  use ExUnit.Case, async: true

  setup_all do
    stylesheet =
      :eirinchan
      |> Application.app_dir("priv/static/recent.css")
      |> File.read!()

    %{stylesheet: stylesheet}
  end

  test "Recent panels consume a shared theme palette", %{stylesheet: stylesheet} do
    assert stylesheet =~ "background: var(--landing-panel-background"
    assert stylesheet =~ "color: var(--landing-panel-color"
    assert stylesheet =~ "border: 1px solid var(--landing-panel-border"
    assert stylesheet =~ "background: var(--landing-panel-heading-background"
    assert stylesheet =~ "color: var(--landing-panel-heading-color"
    assert stylesheet =~ "var(--landing-panel-divider"

    assert stylesheet =~ ".public-boards .board-table {"
    assert stylesheet =~ "color: inherit;"
  end

  test "Tomorrow supplies a dark Recent panel palette", %{stylesheet: stylesheet} do
    assert stylesheet =~ ~s(body[data-stylesheet="tomorrow.css"])
    assert stylesheet =~ "--landing-panel-background: #282a2e;"
    assert stylesheet =~ "--landing-panel-color: #c5c8c6;"
    assert stylesheet =~ "--landing-panel-border: #111;"
    assert stylesheet =~ "--landing-panel-heading-background: #1d1f21;"
    assert stylesheet =~ "--landing-panel-heading-color: #c5c8c6;"
    assert stylesheet =~ "--landing-panel-divider: #3b3d3f;"
  end

  test "the homepage whale reserves its responsive aspect ratio", %{stylesheet: stylesheet} do
    assert stylesheet =~ ".box img.home-page-whales {"
    assert stylesheet =~ "aspect-ratio: 25 / 18;"
    assert stylesheet =~ "height: auto;"
    assert stylesheet =~ "width: 100%;"
  end
end
