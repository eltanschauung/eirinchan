defmodule Eirinchan.SiteContactTest do
  use ExUnit.Case, async: true

  alias Eirinchan.SiteContact

  test "uses the safe default and normalizes instance overrides" do
    assert SiteContact.email(%{}) == "example@example.com"
    assert SiteContact.email(%{contact_email: "  owner@example.test  "}) == "owner@example.test"
    assert SiteContact.email(%{contact_email: "   "}) == "example@example.com"
    assert SiteContact.email(%{contact_email: nil}) == "example@example.com"
  end
end
