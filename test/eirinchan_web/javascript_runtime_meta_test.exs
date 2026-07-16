defmodule EirinchanWeb.JavaScriptRuntimeMetaTest do
  use ExUnit.Case, async: true

  alias EirinchanWeb.PublicShell

  test "custom-code permission is explicit in runtime metadata" do
    config = %{
      allow_user_custom_code: true,
      stylesheets_board: true,
      viewer_timezone: "UTC",
      viewer_timezone_offset_minutes: 0,
      genpassword_chars: "abc"
    }

    assert PublicShell.head_meta(:index, config: config)["eirinchan:allow-user-custom-code"] ==
             "true"
  end

  test "custom code is enabled in the default runtime config" do
    assert Eirinchan.Runtime.Config.default_config().allow_user_custom_code
  end
end
