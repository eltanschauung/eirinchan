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
end
