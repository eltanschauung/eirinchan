defmodule Eirinchan.CountryCodesTest do
  use ExUnit.Case, async: true

  alias Eirinchan.CountryCodes

  test "resolves common, official, and alpha-3 country identifiers" do
    assert CountryCodes.code_for("Germany") == "de"
    assert CountryCodes.code_for("Federal Republic of Germany") == "de"
    assert CountryCodes.code_for("DEU") == "de"
    assert CountryCodes.code_for("South Korea") == "kr"
    assert CountryCodes.code_for("ca") == "ca"
  end

  test "leaves unknown custom flag identifiers for the search normalizer" do
    assert CountryCodes.code_for("mokou") == nil
  end
end
