defmodule Eirinchan.CountryCodesTest do
  use ExUnit.Case, async: true

  alias Eirinchan.CountryCodes

  test "resolves common, official, and alpha-3 country identifiers" do
    assert CountryCodes.code_for("Germany") == "de"
    assert CountryCodes.code_for("Federal Republic of Germany") == "de"
    assert CountryCodes.code_for("DEU") == "de"
    assert CountryCodes.code_for("South Korea") == "kr"
    assert CountryCodes.code_for("ca") == "ca"
    assert CountryCodes.code_for("Turkey") == "tr"
    assert CountryCodes.code_for("Türkiye") == "tr"
  end

  test "leaves unknown custom flag identifiers for the search normalizer" do
    assert CountryCodes.code_for("mokou") == nil
  end

  test "exposes the same search terms for rendered country flags" do
    assert CountryCodes.search_terms_for_code("TR") == [
             "tr",
             "tur",
             "Turkey",
             "Türkiye",
             "Republic of Türkiye"
           ]

    assert CountryCodes.search_terms_for_code("mokou") == []
  end
end
