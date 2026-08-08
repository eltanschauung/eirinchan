defmodule EirinchanWeb.FlagsStylesheetTest do
  use ExUnit.Case, async: true

  test "flags controls inherit the selected theme palette" do
    stylesheet =
      :eirinchan
      |> Application.app_dir("priv/static/stylesheets/eirinchan-public.css")
      |> File.read!()

    assert stylesheet =~
             ".flag-page-controls .postblock{background:transparent;color:inherit;" <>
               "font-weight:700;border:1px solid currentColor"

    refute stylesheet =~ ".flag-page-controls .postblock{color:#800"
    refute stylesheet =~ ".flag-page-controls .postblock{background-color:#ea8"
  end
end
