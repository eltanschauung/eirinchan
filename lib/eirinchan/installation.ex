defmodule Eirinchan.Installation do
  @moduledoc """
  Browser-facing installation/bootstrap support.
  """

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Moderation
  alias Eirinchan.Moderation.ModUser
  alias Eirinchan.Repo
  alias Eirinchan.Settings

  @type setup_result ::
          {:ok, ModUser.t()}
          | {:error, %{errors: map()}}
          | {:error, term()}

  def apply_persisted_repo_config do
    if mix_env() == :test do
      :ok
    else
      case persisted_repo_config() do
        nil -> :ok
        config -> Application.put_env(:eirinchan, Repo, Keyword.merge(Repo.config(), config))
      end
    end
  end

  def setup_required? do
    not admin_exists?()
  rescue
    _ -> true
  end

  def admin_exists? do
    case table_exists?("mod_users") do
      false ->
        false

      true ->
        Repo.exists?(from user in ModUser, select: user.id, limit: 1)
    end
  end

  def setup_defaults do
    config = persisted_repo_config() || runtime_repo_config()

    %{
      "database_hostname" => to_string(Keyword.get(config, :hostname, "localhost")),
      "database_port" => to_string(Keyword.get(config, :port, 5432)),
      "database_name" => to_string(Keyword.get(config, :database, "eirinchan_dev")),
      "database_username" => to_string(Keyword.get(config, :username, "")),
      "database_password" => to_string(Keyword.get(config, :password, "")),
      "database_maintenance" => "postgres",
      "database_maintenance_username" => to_string(Keyword.get(config, :username, "")),
      "database_maintenance_password" => "",
      "admin_username" => "admin",
      "admin_password" => "",
      "admin_password_confirmation" => ""
    }
  end

  def run_setup(attrs) do
    with {:ok, repo_config, create_db_config, admin_attrs} <- normalize_setup(attrs),
         :ok <- create_database(repo_config, create_db_config),
         :ok <- persist_repo_config(repo_config),
         :ok <- reconfigure_repo(repo_config),
         :ok <- migrate(),
         {:ok, admin} <- create_initial_admin(admin_attrs),
         :ok <- initialize_instance_config() do
      {:ok, admin}
    end
  end

  def persist_repo_config(repo_config) when is_list(repo_config) do
    path = config_path()

    payload =
      repo_config
      |> Enum.into(%{})
      |> Map.take([
        :hostname,
        :port,
        :database,
        :username,
        :password,
        :pool_size,
        :show_sensitive_data_on_connection_error
      ])

    path
    |> Path.dirname()
    |> File.mkdir_p!()

    case File.write(path, Jason.encode_to_iodata!(payload, pretty: true)) do
      :ok -> :ok
      {:error, reason} -> {:error, %{errors: %{"storage" => error_string(reason)}}}
    end
  end

  def persisted_repo_config do
    path = config_path()

    with true <- File.exists?(path),
         {:ok, body} <- File.read(path),
         {:ok, decoded} <- Jason.decode(body) do
      decoded
      |> Enum.map(fn {key, value} -> {String.to_atom(key), value} end)
      |> normalize_repo_keyword()
    else
      _ -> nil
    end
  end

  def config_path do
    Application.get_env(:eirinchan, :installation_config_path)
  end

  defp normalize_setup(attrs) do
    attrs = Enum.into(attrs, %{}, fn {key, value} -> {to_string(key), value} end)
    defaults = setup_defaults()
    attrs = Map.merge(defaults, attrs)

    errors =
      %{}
      |> validate_presence(attrs, "database_hostname")
      |> validate_presence(attrs, "database_port")
      |> validate_presence(attrs, "database_name")
      |> validate_presence(attrs, "database_username")
      |> validate_presence(attrs, "admin_username")
      |> validate_presence(attrs, "admin_password")
      |> validate_password_confirmation(attrs)

    if map_size(errors) > 0 do
      {:error, %{errors: errors}}
    else
      repo_config =
        runtime_repo_config()
        |> Keyword.merge(
          hostname: String.trim(attrs["database_hostname"]),
          port: String.to_integer(String.trim(attrs["database_port"])),
          database: String.trim(attrs["database_name"]),
          username: String.trim(attrs["database_username"]),
          password: attrs["database_password"],
          pool_size: 10,
          show_sensitive_data_on_connection_error: true
        )

      create_db_config =
        repo_config
        |> Keyword.merge(
          database: String.trim(attrs["database_maintenance"] || "postgres"),
          username:
            String.trim(
              blank_default(attrs["database_maintenance_username"], attrs["database_username"])
            ),
          password:
            blank_default(attrs["database_maintenance_password"], attrs["database_password"])
        )

      admin_attrs = %{
        "username" => String.trim(attrs["admin_username"]),
        "password" => attrs["admin_password"],
        "role" => "admin"
      }

      {:ok, repo_config, create_db_config, admin_attrs}
    end
  rescue
    ArgumentError ->
      {:error, %{errors: %{"database_port" => "Port must be a valid integer."}}}
  end

  defp create_database(repo_config, create_db_config) do
    case Ecto.Adapters.Postgres.storage_up(repo_config) do
      :ok ->
        :ok

      {:error, :already_up} ->
        :ok

      {:error, _} ->
        create_database_via_postgrex(repo_config, create_db_config)
    end
  end

  defp create_database_via_postgrex(repo_config, create_db_config) do
    connect_opts =
      create_db_config
      |> Keyword.take([
        :hostname,
        :port,
        :username,
        :password,
        :database,
        :show_sensitive_data_on_connection_error
      ])

    with {:ok, pid} <- Postgrex.start_link(connect_opts),
         {:ok, _result} <-
           Postgrex.query(pid, ~s(CREATE DATABASE "#{repo_config[:database]}"), []) do
      GenServer.stop(pid)
      :ok
    else
      {:error, %Postgrex.Error{postgres: %{code: :duplicate_database}}} ->
        :ok

      {:error, reason} ->
        {:error, %{errors: %{"database" => error_string(reason)}}}
    end
  end

  defp reconfigure_repo(repo_config) do
    Application.put_env(:eirinchan, Repo, repo_config)

    if Process.whereis(Repo) do
      _ = Repo.stop()
    end

    wait_for_repo_restart()
  end

  defp wait_for_repo_restart(remaining \\ 50)

  defp wait_for_repo_restart(0) do
    case Repo.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, %{errors: %{"database" => error_string(reason)}}}
    end
  end

  defp wait_for_repo_restart(remaining) do
    if Process.whereis(Repo) do
      :ok
    else
      Process.sleep(100)
      wait_for_repo_restart(remaining - 1)
    end
  end

  defp migrate do
    case Ecto.Migrator.with_repo(Repo, fn repo ->
           Ecto.Migrator.run(repo, Application.app_dir(:eirinchan, "priv/repo/migrations"), :up,
             all: true
           )
         end) do
      {:ok, _, _} ->
        :ok

      {:error, reason} ->
        {:error, %{errors: %{"migration" => error_string(reason)}}}
    end
  end

  defp create_initial_admin(admin_attrs) do
    case admin_exists?() do
      true ->
        {:error, %{errors: %{"admin" => "An administrator already exists."}}}

      false ->
        case Moderation.create_user(admin_attrs) do
          {:ok, admin} -> {:ok, admin}
          {:error, changeset} -> {:error, %{errors: changeset_errors(changeset)}}
        end
    end
  end

  defp initialize_instance_config do
    current = Settings.current_instance_config()

    defaults =
      current
      |> Map.put_new(:uri_flags, "static/flags/%s.png")
      |> Map.put_new(:geoip2_database_path, Application.app_dir(:eirinchan, "priv/geoip2/GeoLite2-Country.mmdb"))
      |> Map.put_new(:max_filesize, 10 * 1024 * 1024)
      |> Map.put_new(:max_links, 20)
      |> Map.put_new(:markup_urls, true)
      |> Map.put_new(:anti_bump_flood, false)
      |> Map.put_new(:force_body, false)
      |> Map.put_new(:force_image_op, true)
      |> Map.put_new(:thumb_width, 208)
      |> Map.put_new(:field_disable_reply_subject, true)
      |> Map.put_new(:catalog_pagination, false)
      |> Map.put_new(:catalog_threads_per_page, 100)
      |> Map.put_new(:noko50_count, 50)
      |> Map.put_new(:noko50_min, 1_000_000)

    Settings.persist_instance_config(defaults)
  end

  defp table_exists?(table_name) do
    case Repo.query("SELECT to_regclass($1)", ["public.#{table_name}"]) do
      {:ok, %{rows: [[nil]]}} -> false
      {:ok, %{rows: [[_name]]}} -> true
      {:error, _reason} -> false
    end
  end

  defp runtime_repo_config do
    Repo.config()
    |> Keyword.take([
      :hostname,
      :port,
      :database,
      :username,
      :password,
      :pool_size,
      :show_sensitive_data_on_connection_error
    ])
    |> normalize_repo_keyword()
  end

  defp normalize_repo_keyword(config) do
    config
    |> Keyword.update(:port, 5432, fn
      port when is_binary(port) -> String.to_integer(port)
      port -> port
    end)
    |> Keyword.put_new(:hostname, "localhost")
    |> Keyword.put_new(:port, 5432)
  end

  defp validate_presence(errors, attrs, field) do
    if blank?(attrs[field]) do
      Map.put(errors, field, "This field is required.")
    else
      errors
    end
  end

  defp validate_password_confirmation(errors, attrs) do
    if attrs["admin_password"] == attrs["admin_password_confirmation"] do
      errors
    else
      Map.put(errors, "admin_password_confirmation", "Passwords do not match.")
    end
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_value), do: false

  defp blank_default(value, fallback) do
    if blank?(value), do: fallback, else: value
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp error_string(%{message: message}) when is_binary(message), do: message
  defp error_string(reason) when is_binary(reason), do: reason
  defp error_string(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_string(reason), do: inspect(reason)

  defp mix_env do
    if Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) do
      Mix.env()
    else
      :prod
    end
  end
end
