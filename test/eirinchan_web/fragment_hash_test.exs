defmodule EirinchanWeb.FragmentHashTest do
  use ExUnit.Case, async: true

  alias EirinchanWeb.FragmentHash

  test "equivalent independently compiled regexes have a stable config digest" do
    config = fn ->
      %{nested: [{:referer_match, Regex.compile!("^https://example.test/", "i")}]}
    end

    assert FragmentHash.term_digest(config.()) == FragmentHash.term_digest(config.())
  end

  test "regex source and options remain part of the digest" do
    digest = FragmentHash.term_digest(%{referer_match: Regex.compile!("example", "i")})

    refute digest == FragmentHash.term_digest(%{referer_match: Regex.compile!("other", "i")})
    refute digest == FragmentHash.term_digest(%{referer_match: Regex.compile!("example")})
  end

  test "config digests support structs without an Enumerable implementation" do
    assert is_binary(
             FragmentHash.term_digest(%{board: %Eirinchan.Boards.Board{uri: "b", title: "Random"}})
           )
  end
end
