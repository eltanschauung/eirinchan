defmodule Eirinchan.MediaProcessing do
  @moduledoc "Bounded, fail-fast admission for media jobs and external commands."
  use GenServer

  @inside_key {__MODULE__, :inside}

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, %{}, name: Keyword.get(opts, :name, __MODULE__))

  def run(fun, opts \\ []) when is_function(fun, 0) do
    if Process.get(@inside_key, false) do
      fun.()
    else
      configured_limit =
        if Map.has_key?(
             Eirinchan.Settings.current_instance_config(),
             :media_processing_concurrency
           ),
           do: Eirinchan.Settings.effective_instance_config().media_processing_concurrency,
           else: Application.get_env(:eirinchan, :media_processing_concurrency, 2)

      limit = Keyword.get(opts, :limit, configured_limit)
      cleanup = Keyword.get(opts, :cleanup, fn _ -> :ok end)
      server = Keyword.get(opts, :server, __MODULE__)

      case GenServer.call(server, {:run, fun, cleanup, limit}, :infinity) do
        {:completed, value} -> value
        {:raised, kind, reason, stack} -> :erlang.raise(kind, reason, stack)
        {:error, _} = error -> error
      end
    end
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:run, fun, cleanup, limit}, from, jobs) do
    limit = if is_integer(limit) and limit in 1..8, do: limit, else: 2

    if map_size(jobs) >= limit do
      {:reply, {:error, :media_busy}, jobs}
    else
      task =
        Task.Supervisor.async_nolink(Eirinchan.MediaTaskSupervisor, fn ->
          Process.put(@inside_key, true)

          try do
            {:completed, fun.()}
          catch
            kind, reason -> {:raised, kind, reason, __STACKTRACE__}
          end
        end)

      # A disconnected requester must not free a slot while its OS command is
      # still running. The independent worker remains admitted until completion.
      {:noreply, Map.put(jobs, task.ref, %{from: from, cleanup: cleanup})}
    end
  end

  @impl true
  def handle_info({ref, result}, jobs) when is_reference(ref) do
    case Map.pop(jobs, ref) do
      {nil, jobs} ->
        {:noreply, jobs}

      {%{from: {owner, _} = from, cleanup: cleanup}, jobs} ->
        Process.demonitor(ref, [:flush])

        if Process.alive?(owner) do
          GenServer.reply(from, result)
        else
          case result do
            {:completed, value} -> safely_cleanup(cleanup, value)
            _ -> :ok
          end
        end

        {:noreply, jobs}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, jobs) do
    case Map.pop(jobs, ref) do
      {nil, jobs} ->
        {:noreply, jobs}

      {%{from: from}, jobs} ->
        GenServer.reply(from, {:error, :upload_failed})
        {:noreply, jobs}
    end
  end

  def handle_info(_message, jobs), do: {:noreply, jobs}

  defp safely_cleanup(cleanup, value) do
    cleanup.(value)
  catch
    _, _ -> :ok
  end
end
