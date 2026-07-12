defmodule EirinchanWeb.Param do
  @moduledoc false

  @max_database_id 2_147_483_647

  def integer(value) when is_integer(value), do: {:ok, value}

  def integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> :error
    end
  end

  def integer(_value), do: :error

  def positive_integer(value) do
    case integer(value) do
      {:ok, parsed} when parsed > 0 -> {:ok, parsed}
      _ -> :error
    end
  end

  def database_id(value) do
    case integer(value) do
      {:ok, parsed} when parsed > 0 and parsed <= @max_database_id -> {:ok, parsed}
      _ -> :error
    end
  end

  def bounded_integer(value, default, opts \\ [])
      when is_integer(default) and is_list(opts) do
    minimum = Keyword.get(opts, :min, 1)
    maximum = Keyword.get(opts, :max, max(default, minimum))

    case integer(value) do
      {:ok, parsed} -> parsed |> max(minimum) |> min(maximum)
      :error -> default |> max(minimum) |> min(maximum)
    end
  end
end
