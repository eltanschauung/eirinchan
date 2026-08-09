defmodule EirinchanWeb.UserFlagPreferenceTest do
  use ExUnit.Case, async: true

  import Plug.Conn, only: [put_req_header: 3]
  import Plug.Test

  alias EirinchanWeb.UserFlagPreference

  @config %{
    user_flag: true,
    multiple_flags: true,
    default_user_flag: "country",
    user_flags: %{"meiling" => "Meiling", "tenshi" => "Tenshi"},
    country_flag_fallback: %{code: "us", name: "United States"}
  }

  test "returns the configured default when the preference cookie is absent" do
    assert UserFlagPreference.value(conn(:get, "/"), @config) == "country"
  end

  test "normalizes a valid cookie using the same tokens accepted by posts" do
    conn =
      conn(:get, "/") |> put_req_cookie(UserFlagPreference.cookie_name(), " Country, MEILING ")

    assert UserFlagPreference.value(conn, @config) == "country,meiling"
  end

  test "decodes the percent-encoded cookie syntax sent by browsers" do
    conn =
      conn(:get, "/")
      |> put_req_header("cookie", "eirinchan_user_flag=country%2Cmeiling")

    assert UserFlagPreference.value(conn, @config) == "country,meiling"
  end

  test "rejects unknown, oversized, and multiple values when they are not allowed" do
    assert UserFlagPreference.normalize("missing", @config) == :error
    assert UserFlagPreference.normalize(String.duplicate("a", 301), @config) == :error

    single_config = Map.put(@config, :multiple_flags, false)
    assert UserFlagPreference.normalize("country,meiling", single_config) == :error
    assert UserFlagPreference.normalize("meiling", single_config) == {:ok, "meiling"}
  end

  test "accepts the country fallback and an intentionally blank field" do
    assert UserFlagPreference.normalize("US", @config) == {:ok, "us"}
    assert UserFlagPreference.normalize("  ", @config) == {:ok, ""}
  end

  test "ignores the cookie when user-selectable flags are disabled" do
    conn = conn(:get, "/") |> put_req_cookie(UserFlagPreference.cookie_name(), "meiling")

    assert UserFlagPreference.value(conn, Map.put(@config, :user_flag, false)) == "country"
  end

  test "lists only the canonical values exposed to the browser" do
    assert UserFlagPreference.allowed_values(@config) == ["country", "meiling", "tenshi", "us"]
  end
end
