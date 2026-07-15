defmodule Eirinchan.DefaultCountryFlagsTest do
  use ExUnit.Case, async: true

  @flag_dir Path.expand("../../priv/static/static/flags", __DIR__)
  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  test "ships the pinned upstream country flag set with safe PNG filenames" do
    flags = Path.wildcard(Path.join(@flag_dir, "*.png"))
    filenames = Enum.map(flags, &Path.basename/1)

    assert length(flags) == 275

    for expected <- ~w(ca.png gb.png jp.png us.png xx.png) do
      assert expected in filenames
    end

    Enum.each(flags, fn path ->
      assert Regex.match?(~r/^[a-z0-9_]+\.png$/, Path.basename(path))
      assert {:ok, @png_signature} = File.open(path, [:read, :binary], &IO.binread(&1, 8))
    end)
  end
end
