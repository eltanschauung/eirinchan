defmodule Eirinchan.SettingsTest do
  use ExUnit.Case, async: false

  alias Eirinchan.Settings

  setup do
    original_path = Application.get_env(:eirinchan, :instance_config_path)

    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-settings-#{System.unique_integer([:positive])}.json"
      )

    File.rm(path)
    Application.put_env(:eirinchan, :instance_config_path, path)
    Settings.refresh_instance_config_cache()

    on_exit(fn ->
      Application.put_env(:eirinchan, :instance_config_path, original_path)
      Settings.refresh_instance_config_cache()
      File.rm(path)
    end)

    :ok
  end

  test "current_instance_config is refreshed after persisting new config" do
    assert Settings.current_instance_config() == %{}

    assert :ok = Settings.persist_instance_config(%{anonymous: "Anon"})
    assert Settings.current_instance_config().anonymous == "Anon"

    assert :ok = Settings.persist_instance_config(%{anonymous: "Nameless"})
    assert Settings.current_instance_config().anonymous == "Nameless"
  end

  test "persisted settings are atomically replaced with owner-only permissions" do
    path = Application.fetch_env!(:eirinchan, :instance_config_path)
    File.write!(path, "{}")
    File.chmod!(path, 0o644)

    assert :ok = Settings.persist_instance_config(%{captcha: %{secret: "sensitive"}})
    assert File.stat!(path).mode |> Bitwise.band(0o777) == 0o600
    assert Jason.decode!(File.read!(path))["captcha"]["secret"] == "sensitive"
    assert Path.wildcard(Path.join(Path.dirname(path), ".#{Path.basename(path)}.*.tmp")) == []
  end

  test "IP access passwords are hashed before settings are persisted" do
    assert :ok = Settings.persist_instance_config(%{ip_access_passwords: ["Door", "other"]})

    stored = Settings.current_instance_config().ip_access_passwords
    assert length(stored) == 2
    assert Enum.any?(stored, &Eirinchan.CredentialHash.verify("door", &1, :ip_access))
    refute File.read!(Application.fetch_env!(:eirinchan, :instance_config_path)) =~ "Door"
  end

  test "raw settings preserve authored JSON unless sensitive values require rewriting" do
    raw_json = "{\n  \"Flags\": \"/flags\",\n  \"Home\": \"/\"\n}\n"

    assert :ok = Settings.persist_instance_config_raw_json(raw_json)
    assert Settings.raw_instance_config_json() == raw_json

    assert :ok =
             Settings.persist_instance_config_raw_json(
               ~s({"ip_access_passwords":["Door"],"anonymous":"Anon"})
             )

    persisted = File.read!(Application.fetch_env!(:eirinchan, :instance_config_path))
    refute persisted =~ "Door"

    [stored_password] = Settings.current_instance_config().ip_access_passwords
    assert Eirinchan.CredentialHash.verify("door", stored_password, :ip_access)
  end

  test "persist_instance_config preserves page theme state when overrides omit it" do
    assert :ok =
             Settings.persist_instance_config(%{
               anonymous: "Anon",
               template_themes: %{installed: %{"catalog" => %{}}},
               themes: %{page_enabled: ["catalog"]}
             })

    assert :ok = Settings.persist_instance_config(%{anonymous: "Nameless"})

    config = Settings.current_instance_config()
    assert config.template_themes.installed[:catalog] == %{}
    assert config.themes.page_enabled == ["catalog"]
  end

  test "theme updates preserve existing theme metadata" do
    assert :ok =
             Settings.persist_instance_config(%{
               themes: %{public: ["christmas"], page_enabled: ["catalog"]}
             })

    assert :ok = Settings.set_default_theme("christmas")

    config = Settings.current_instance_config()
    assert config.themes.public == ["christmas"]
    assert config.themes.page_enabled == ["catalog"]
    assert config.themes.default == "christmas"
  end
end
