defmodule EirinchanWeb.PostFormStylesheetTest do
  use ExUnit.Case, async: true

  test "new-thread and reply flag fields match their comment textarea width" do
    stylesheet =
      :eirinchan
      |> Application.app_dir("priv/static/stylesheets/eirinchan-public.css")
      |> File.read!()

    assert stylesheet =~
             "#new-thread-form textarea[name=body],#new-thread-form [name=user_flag]," <>
               "#reply-form textarea[name=body],#reply-form [name=user_flag]" <>
               "{box-sizing:border-box;width:100%}"
  end
end
