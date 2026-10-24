defmodule Eirinchan.RuntimeCredentialsTest do
  use ExUnit.Case, async: false

  test "production runtime accepts private credential files without reading operator env scripts" do
    keys =
      ~w(DATABASE_URL DATABASE_URL_FILE SECRET_KEY_BASE SECRET_KEY_BASE_FILE EIRINCHAN_STATE_ROOT PHX_SERVER)

    original = Map.new(keys, &{&1, System.get_env(&1)})

    directory =
      Path.join(System.tmp_dir!(), "runtime-credentials-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    secret = String.duplicate("test-only-key-", 6)
    database = "ecto://fixture:dummy@127.0.0.1/isolated_fixture"
    File.write!(Path.join(directory, "key"), secret <> "\n")
    File.write!(Path.join(directory, "database"), database <> "\n")

    try do
      Enum.each(keys, &System.delete_env/1)
      System.put_env("SECRET_KEY_BASE_FILE", Path.join(directory, "key"))
      System.put_env("DATABASE_URL_FILE", Path.join(directory, "database"))
      System.put_env("EIRINCHAN_STATE_ROOT", directory)
      config = Config.Reader.read!("config/runtime.exs", env: :prod)
      assert config[:eirinchan][Eirinchan.Repo][:url] == database
      assert config[:eirinchan][EirinchanWeb.Endpoint][:secret_key_base] == secret

      assert config[:eirinchan][:instance_config_path] ==
               Path.join(directory, "var/settings.json")

      File.rm!(Path.join(directory, "key"))
      assert_raise File.Error, fn -> Config.Reader.read!("config/runtime.exs", env: :prod) end
    after
      for {key, value} <- original do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end

      File.rm_rf!(directory)
    end
  end
end
