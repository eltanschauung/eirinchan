defmodule Eirinchan.Moderation.ModUser do
  use Ecto.Schema
  import Ecto.Changeset

  alias Eirinchan.Moderation.ModBoardAccess
  alias Eirinchan.Runtime.Config

  @argon2_salt_marker "argon2id:v1"

  schema "mod_users" do
    field :username, :string
    field :password_hash, :string
    field :password_salt, :string
    field :role, :string, default: "admin"
    field :all_boards, :boolean, default: false
    field :last_login_at, :utc_datetime_usec
    field :password, :string, virtual: true

    has_many :board_accesses, ModBoardAccess

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(user, attrs), do: create_changeset(user, attrs, Config.default_config())

  def create_changeset(user, attrs, config) do
    limits = credential_limits(config)

    user
    |> cast(attrs, [:username, :password, :role, :all_boards, :last_login_at])
    |> update_change(:username, &normalize_string/1)
    |> normalize_optional_password()
    |> validate_required([:username, :password, :role])
    |> validate_length(:username, min: 1, max: limits.username_max)
    |> validate_length(:password, min: limits.password_min, max: limits.password_max)
    |> validate_inclusion(:role, ["admin", "mod", "janitor"])
    |> put_password_fields()
    |> validate_required([:password_hash, :password_salt])
    |> unique_constraint(:username)
  end

  def login_changeset(user, attrs) do
    user
    |> cast(attrs, [:last_login_at])
  end

  def update_changeset(user, attrs), do: update_changeset(user, attrs, Config.default_config())

  def update_changeset(user, attrs, config) do
    limits = credential_limits(config)

    user
    |> cast(attrs, [:username, :password, :role, :all_boards])
    |> update_change(:username, &normalize_string/1)
    |> normalize_optional_password()
    |> validate_required([:username, :role])
    |> validate_length(:username, min: 1, max: limits.username_max)
    |> validate_length(:password, min: limits.password_min, max: limits.password_max)
    |> validate_inclusion(:role, ["admin", "mod", "janitor"])
    |> put_password_fields()
    |> unique_constraint(:username)
  end

  def credential_limits(config) do
    username_max = bounded(config, :mod_username_max_length, 64, 1, 255)
    password_max = bounded(config, :mod_password_max_length, 255, 12, 4_096)
    password_min = bounded(config, :mod_password_min_length, 12, 12, password_max)

    %{username_max: username_max, password_min: password_min, password_max: password_max}
  end

  defp bounded(config, key, default, minimum, maximum) do
    value = Map.get(config, key, default)
    if is_integer(value), do: value |> max(minimum) |> min(maximum), else: default
  end

  defp put_password_fields(changeset) do
    case get_change(changeset, :password) do
      nil ->
        changeset

      password ->
        changeset
        |> put_change(:password_salt, @argon2_salt_marker)
        |> put_change(:password_hash, Argon2.hash_pwd_salt(password))
    end
  end

  def verify_password(%__MODULE__{} = user, password) when is_binary(password) do
    cond do
      legacy_vichan_password?(user) ->
        verify_legacy_vichan_password(user.password_hash || "", password)

      argon2_password?(user) ->
        Argon2.verify_pass(password, user.password_hash)

      true ->
        expected = legacy_sha256_hash(password, user.password_salt || "")
        Plug.Crypto.secure_compare(user.password_hash || "", expected)
    end
  end

  def verify_password(_user, _password), do: false

  def legacy_vichan_password?(%__MODULE__{password_salt: "legacy:vichan:" <> _}), do: true
  def legacy_vichan_password?(_user), do: false

  def password_needs_rehash?(%__MODULE__{} = user), do: not argon2_password?(user)

  def upgrade_password_changeset(%__MODULE__{} = user, password) when is_binary(password) do
    change(user,
      password_hash: Argon2.hash_pwd_salt(password),
      password_salt: @argon2_salt_marker
    )
  end

  defp argon2_password?(%__MODULE__{password_hash: "$argon2" <> _rest}), do: true
  defp argon2_password?(_user), do: false

  defp legacy_sha256_hash(password, salt) do
    :crypto.hash(:sha256, salt <> password)
    |> Base.encode16(case: :lower)
  end

  defp verify_legacy_vichan_password(stored_hash, password) do
    case Regex.run(~r/^\$6\$(?:rounds=(\d+)\$)?([^$]+)\$[A-Za-z0-9.\/]+$/, stored_hash) do
      [_, rounds, salt] ->
        args =
          ["--stdin", "--method=sha-512"] ++
            if(rounds != "", do: ["--rounds", rounds], else: []) ++ ["--salt", salt]

        case run_mkpasswd(args, password) do
          {computed, 0} ->
            Plug.Crypto.secure_compare(String.trim(computed), stored_hash)

          _ ->
            false
        end

      _ ->
        false
    end
  end

  defp run_mkpasswd(args, password) do
    with executable when is_binary(executable) <- System.find_executable("mkpasswd"),
         port <-
           Port.open({:spawn_executable, executable}, [
             :binary,
             :exit_status,
             :stderr_to_stdout,
             args: args
           ]),
         true <- Port.command(port, password <> "\n") do
      collect_port_output(port, "")
    else
      _error -> {"", 1}
    end
  end

  defp collect_port_output(port, output) do
    receive do
      {^port, {:data, data}} -> collect_port_output(port, output <> data)
      {^port, {:exit_status, status}} -> {output, status}
    after
      5_000 ->
        Port.close(port)
        {output, 1}
    end
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_password(changeset) do
    case get_change(changeset, :password) do
      value when is_binary(value) ->
        trimmed = String.trim(value)

        if trimmed == "" do
          delete_change(changeset, :password)
        else
          put_change(changeset, :password, trimmed)
        end

      _ ->
        changeset
    end
  end
end
