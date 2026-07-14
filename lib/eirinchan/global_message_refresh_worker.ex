defmodule Eirinchan.GlobalMessageRefreshWorker do
  @moduledoc false

  use GenServer

  require Logger

  alias Eirinchan.Settings
  alias EirinchanWeb.Announcements

  @default_interval_seconds 30

  def start_link(opts \\ []) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  def refresh_now(server \\ __MODULE__), do: GenServer.call(server, :refresh)

  @doc false
  def interval_seconds(config) when is_map(config) do
    case Map.get(config, :global_message_refresh_seconds, @default_interval_seconds) do
      seconds when is_integer(seconds) and seconds > 0 -> seconds
      _other -> @default_interval_seconds
    end
  end

  def interval_seconds(_config), do: @default_interval_seconds

  @impl true
  def init(opts) do
    state = %{
      config_provider: Keyword.get(opts, :config_provider, &Settings.current_instance_config/0),
      refresh: Keyword.get(opts, :refresh, &Announcements.refresh_cache/0)
    }

    initial_delay =
      Keyword.get_lazy(opts, :initial_delay_ms, fn ->
        next_interval_ms(state.config_provider.())
      end)

    schedule(initial_delay)
    {:ok, state}
  end

  @impl true
  def handle_call(:refresh, _from, state) do
    {:reply, safe_refresh(state.refresh), state}
  end

  @impl true
  def handle_info(:refresh, state) do
    _ = safe_refresh(state.refresh)
    schedule(next_interval_ms(state.config_provider.()))
    {:noreply, state}
  end

  defp safe_refresh(refresh) do
    refresh.()
  rescue
    error ->
      Logger.error("global message cache refresh failed: #{Exception.message(error)}")
      {:error, error}
  end

  defp next_interval_ms(config), do: interval_seconds(config) * 1_000
  defp schedule(delay_ms), do: Process.send_after(self(), :refresh, delay_ms)
end
