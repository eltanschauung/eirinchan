defmodule Eirinchan.WhaleStickers.DefaultsTest do
  use ExUnit.Case, async: true

  alias Eirinchan.WhaleStickers.Defaults

  test "woof is a packaged default sticker and renders through the replacement system" do
    assert %{token: "woof", file: "woof.png", title: "woof", append_break: false} in Defaults.entries()

    assert Eirinchan.WhaleStickers.contains_sticker?(":woof:", %{})
    html = Eirinchan.WhaleStickers.replace_line(":woof: hello", %{})

    assert html =~ ~s(src="/whalestickers/woof.png")
    assert html =~ ~s(title=":woof:")
    assert html =~ ~s(width="137" height="79")
    assert String.ends_with?(html, " hello")
  end

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
