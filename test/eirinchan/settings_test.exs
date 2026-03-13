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
end
