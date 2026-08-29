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

  test "formatting columns contain every default sticker exactly once" do
    columns = Defaults.formatting_columns()
    configured_tokens = Defaults.entries() |> Enum.map(& &1.token) |> Enum.sort()
    formatting_tokens = columns |> Map.values() |> List.flatten()

    assert Enum.sort(formatting_tokens) == configured_tokens
    assert length(formatting_tokens) == length(Enum.uniq(formatting_tokens))
    assert length(columns.left) == 52
    assert hd(columns.left) == "gem"
  end
end
