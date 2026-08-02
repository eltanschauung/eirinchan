defmodule EirinchanWeb.StatisticsStylesheetTest do
  use ExUnit.Case, async: true

  setup_all do
    stylesheet =
      :eirinchan
      |> Application.app_dir("priv/static/stats.css")
      |> File.read!()

    %{stylesheet: stylesheet}
  end

  test "chart layout is theme-neutral and reserves every server-rendered column", %{
    stylesheet: stylesheet
  } do
    assert stylesheet =~ "color: inherit;"
    assert stylesheet =~ "border: 1px solid currentColor;"
    assert stylesheet =~ "repeat(var(--statistics-column-count)"
    assert stylesheet =~ "min-width: calc(var(--statistics-column-count) * 2.75rem);"
    assert stylesheet =~ "overflow-x: auto;"
    assert stylesheet =~ "height: var(--statistics-bar-height);"
    refute stylesheet =~ "background: white"
    refute stylesheet =~ "color: black"
  end
end
