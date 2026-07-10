defmodule Eirinchan.SecureFile do
  @moduledoc false

  @default_mode 0o600

  def atomic_write(path, contents, opts \\ []) when is_binary(path) do
    mode = Keyword.get(opts, :mode, @default_mode)
    directory = Path.dirname(path)
    temporary = temporary_path(path)

    with :ok <- File.mkdir_p(directory),
         {:ok, io} <- File.open(temporary, [:write, :binary, :exclusive]),
         :ok <- write_and_close(io, temporary, contents, mode),
         :ok <- File.rename(temporary, path),
         :ok <- File.chmod(path, mode) do
      :ok
    else
      {:error, _reason} = error ->
        File.rm(temporary)
        error
    end
  end

  defp write_and_close(io, path, contents, mode) do
    result =
      with :ok <- File.chmod(path, mode),
           :ok <- IO.binwrite(io, contents),
           :ok <- :file.sync(io) do
        :ok
      end

    close_result = File.close(io)

    case {result, close_result} do
      {:ok, :ok} -> :ok
      {{:error, _reason} = error, _close_result} -> error
      {:ok, {:error, _reason} = error} -> error
    end
  end

  defp temporary_path(path) do
    suffix = System.unique_integer([:positive, :monotonic])
    Path.join(Path.dirname(path), ".#{Path.basename(path)}.#{suffix}.tmp")
  end
end
