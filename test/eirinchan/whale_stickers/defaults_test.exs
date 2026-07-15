defmodule Eirinchan.WhaleStickers.DefaultsTest do
  use ExUnit.Case, async: true

  alias Eirinchan.WhaleStickers.Defaults

  test "every configured default sticker is packaged with the application" do
    missing =
      Defaults.entries()
      |> Enum.map(& &1.file)
      |> Enum.uniq()
      |> Enum.reject(fn file ->
        :eirinchan
        |> Application.app_dir(Path.join(["priv", "static", "whalestickers", file]))
        |> File.regular?()
      end)

    assert missing == []
  end
end
