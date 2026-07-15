defmodule EirinchanWeb.BantStaticAssetsTest do
  use ExUnit.Case, async: true

  @assets [
    "error_pages/sanae.png",
    "site_logo.png",
    "site_logo2_recent.png",
    "whales.jpg"
  ]

  test "packages Bant-specific public assets with the application" do
    missing =
      Enum.reject(@assets, fn asset ->
        :eirinchan
        |> Application.app_dir(Path.join(["priv", "static", asset]))
        |> File.regular?()
      end)

    assert missing == [],
           """
           Bant-specific assets must be tracked so detached release builds include them.
           Missing: #{inspect(missing)}
           """
  end
end
