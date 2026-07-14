defmodule Eirinchan.AccessLog do
  @moduledoc false

  use GenServer

  require Logger

  @reopen_interval_ms 5_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def write(line, server \\ __MODULE__) do
    GenServer.call(server, {:write, IO.iodata_to_binary(line)}, 5_000)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def purge_older_than(%DateTime{} = cutoff, server \\ __MODULE__) do
    GenServer.call(server, {:purge_older_than, cutoff}, 120_000)
  end

  def stats(server \\ __MODULE__) do
    GenServer.call(server, :stats)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @impl true
  def init(opts) do
    path = Keyword.get(opts, :path) || Application.fetch_env!(:eirinchan, :access_log_path)
    path = Path.expand(path)

    state = %{
      path: path,
      io: nil,
      reopen_after: 0,
      writes: 0,
      write_errors: 0,
      purged_lines: 0
    }

    {:ok, open_log(state)}
  end

  @impl true
  def handle_call({:write, line}, _from, state) do
    state = maybe_reopen(state)

    case write_line(state, line) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason, state} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:purge_older_than, cutoff}, _from, state) do
    state = close_log(state)

    case purge_file(state.path, cutoff) do
      {:ok, removed} ->
        {:reply, {:ok, removed}, open_log(%{state | purged_lines: state.purged_lines + removed})}

      {:error, reason} ->
        Logger.error("failed to purge access log: #{inspect(reason)}")
        {:reply, {:error, reason}, open_log(state)}
    end
  end

  def handle_call(:stats, _from, state) do
    {:reply, Map.take(state, [:writes, :write_errors, :purged_lines]), state}
  end

  @impl true
  def terminate(_reason, state) do
    _ = close_log(state)
    :ok
  end

  defp write_line(%{io: nil} = state, _line) do
    {:error, :unavailable, %{state | write_errors: state.write_errors + 1}}
  end

  defp write_line(%{io: io} = state, line) do
    case IO.write(io, line) do
      :ok ->
        {:ok, %{state | writes: state.writes + 1}}

      {:error, reason} ->
        Logger.error("failed to write access log: #{inspect(reason)}")

        {:error, reason,
         state
         |> close_log()
         |> Map.put(:reopen_after, monotonic_milliseconds() + @reopen_interval_ms)
         |> Map.update!(:write_errors, &(&1 + 1))}
    end
  rescue
    error ->
      Logger.error("failed to write access log: #{Exception.message(error)}")

      {:error, error,
       state
       |> close_log()
       |> Map.put(:reopen_after, monotonic_milliseconds() + @reopen_interval_ms)
       |> Map.update!(:write_errors, &(&1 + 1))}
  end

  defp maybe_reopen(%{io: nil, reopen_after: reopen_after} = state) do
    if monotonic_milliseconds() >= reopen_after, do: open_log(state), else: state
  end

  defp maybe_reopen(state), do: state

  defp open_log(state) do
    File.mkdir_p!(Path.dirname(state.path))

    case File.open(state.path, [:append, :utf8]) do
      {:ok, io} ->
        _ = File.chmod(state.path, 0o600)
        %{state | io: io, reopen_after: 0}

      {:error, reason} ->
        Logger.error("failed to open access log: #{inspect(reason)}")
        %{state | io: nil, reopen_after: monotonic_milliseconds() + @reopen_interval_ms}
    end
  rescue
    error ->
      Logger.error("failed to open access log: #{Exception.message(error)}")
      %{state | io: nil, reopen_after: monotonic_milliseconds() + @reopen_interval_ms}
  end

  defp close_log(%{io: nil} = state), do: state

  defp close_log(%{io: io} = state) do
    _ = File.close(io)
    %{state | io: nil}
  end

  defp purge_file(path, cutoff) do
    if File.exists?(path) do
      temp_path = path <> ".purge-" <> Integer.to_string(System.unique_integer([:positive]))

      try do
        {:ok, output} = File.open(temp_path, [:write, :exclusive, :utf8])
        _ = File.chmod(temp_path, 0o600)

        {kept, removed} =
          path
          |> File.stream!(:line, [])
          |> Enum.reduce({0, 0}, fn line, {kept, removed} ->
            if expired_line?(line, cutoff) do
              {kept, removed + 1}
            else
              :ok = IO.write(output, line)
              {kept + 1, removed}
            end
          end)

        :ok = File.close(output)
        :ok = File.rename(temp_path, path)
        _ = File.chmod(path, 0o600)
        _ = kept
        {:ok, removed}
      rescue
        error ->
          _ = File.rm(temp_path)
          {:error, error}
      catch
        kind, reason ->
          _ = File.rm(temp_path)
          {:error, {kind, reason}}
      end
    else
      {:ok, 0}
    end
  end

  defp expired_line?(line, cutoff) do
    case parse_timestamp(line) do
      {:ok, timestamp} -> DateTime.compare(timestamp, cutoff) == :lt
      :error -> false
    end
  end

  @months %{
    "Jan" => 1,
    "Feb" => 2,
    "Mar" => 3,
    "Apr" => 4,
    "May" => 5,
    "Jun" => 6,
    "Jul" => 7,
    "Aug" => 8,
    "Sep" => 9,
    "Oct" => 10,
    "Nov" => 11,
    "Dec" => 12
  }

  defp parse_timestamp(line) do
    pattern =
      ~r/\[(\d{2})\/([A-Z][a-z]{2})\/(\d{4}):(\d{2}):(\d{2}):(\d{2}) \+0000\]/

    with [_, day, month, year, hour, minute, second] <- Regex.run(pattern, line),
         month_number when is_integer(month_number) <- Map.get(@months, month),
         {:ok, date} <- Date.new(to_integer(year), month_number, to_integer(day)),
         {:ok, time} <- Time.new(to_integer(hour), to_integer(minute), to_integer(second)),
         {:ok, timestamp} <- DateTime.new(date, time, "Etc/UTC") do
      {:ok, timestamp}
    else
      _ -> :error
    end
  end

  defp to_integer(value), do: String.to_integer(value)
  defp monotonic_milliseconds, do: System.monotonic_time(:millisecond)
end
