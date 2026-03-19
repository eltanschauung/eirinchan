defmodule Eirinchan.Moderation.ModUser do
  use Ecto.Schema
  import Ecto.Changeset

  alias Eirinchan.Moderation.ModBoardAccess

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

  def create_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :password, :role, :all_boards, :last_login_at])
    |> update_change(:username, &normalize_string/1)
    |> normalize_optional_password()
    |> validate_required([:username, :password, :role])
    |> validate_length(:username, min: 1, max: 64)
    |> validate_length(:password, min: 1, max: 255)
    |> validate_inclusion(:role, ["admin", "mod", "janitor"])
    |> put_password_fields()
    |> validate_required([:password_hash, :password_salt])
    |> unique_constraint(:username)
  end

  def login_changeset(user, attrs) do
    user
    |> cast(attrs, [:last_login_at])
  end

  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :password, :role, :all_boards])
    |> update_change(:username, &normalize_string/1)
    |> normalize_optional_password()
    |> validate_required([:username, :role])
    |> validate_length(:username, min: 1, max: 64)
    |> validate_length(:password, min: 1, max: 255)
    |> validate_inclusion(:role, ["admin", "mod", "janitor"])
    |> put_password_fields()
    |> unique_constraint(:username)
  end

  defp put_password_fields(changeset) do
    case get_change(changeset, :password) do
      nil ->
        changeset

      password ->
        salt = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
        hash = hash_password(password, salt)

        changeset
        |> put_change(:password_salt, salt)
        |> put_change(:password_hash, hash)
    end
  end

  def verify_password(%__MODULE__{} = user, password) when is_binary(password) do
    cond do
      legacy_vichan_password?(user) ->
        verify_legacy_vichan_password(user.password_hash || "", password)

      true ->
        expected = hash_password(password, user.password_salt || "")
        Plug.Crypto.secure_compare(user.password_hash || "", expected)
    end
  end

  def verify_password(_user, _password), do: false

  def legacy_vichan_password?(%__MODULE__{password_salt: "legacy:vichan:" <> _}), do: true
  def legacy_vichan_password?(_user), do: false

  def upgrade_legacy_password_changeset(%__MODULE__{} = user, password) when is_binary(password) do
    salt = generate_password_salt()
    hash = hash_password(password, salt)
    change(user, password_hash: hash, password_salt: salt)
  end

  defp hash_password(password, salt) do
    :crypto.hash(:sha256, salt <> password)
    |> Base.encode16(case: :lower)
  end

  defp generate_password_salt do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp verify_legacy_vichan_password(stored_hash, password) do
    case Regex.run(~r/^\$6\$(?:rounds=(\d+)\$)?([^$]+)\$[A-Za-z0-9.\/]+$/, stored_hash) do
      [_, rounds, salt] ->
        args =
          ["--method=sha-512"] ++
            if(rounds != "", do: ["--rounds", rounds], else: []) ++ ["--salt", salt, password]

        case System.cmd("mkpasswd", args, stderr_to_stdout: true) do
          {computed, 0} ->
            Plug.Crypto.secure_compare(String.trim(computed), stored_hash)

          _ ->
            false
        end

      _ ->
        false
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
