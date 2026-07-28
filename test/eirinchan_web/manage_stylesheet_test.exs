defmodule EirinchanWeb.ManageStylesheetTest do
  use ExUnit.Case, async: true

  test "manage layout rules do not impose the Yotsuba palette" do
    stylesheet =
      :eirinchan
      |> Application.app_dir("priv/static/stylesheets/eirinchan-mod.css")
      |> File.read!()

    refute stylesheet =~ "fade-yotsuba"
    refute stylesheet =~ "background-color: #ea8"
    refute stylesheet =~ "color: #800"
    refute stylesheet =~ "background: rgba(240, 224, 214"
  end

  test "Tomorrow uses its dark panel color for moderation log headers" do
    stylesheet =
      :eirinchan
      |> Application.app_dir("priv/static/stylesheets/tomorrow.css")
      |> File.read!()

    assert stylesheet =~ "table.modlog tr th{background:#282a2e}"
    refute stylesheet =~ "table.modlog tr th{background:#EA8}"
  end
end
