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
