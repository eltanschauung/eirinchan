defmodule Eirinchan.BrowserAbuse do
  @moduledoc """
  Maintains short-lived browser risk signals used only for challenge escalation.

  These signals are deliberately separate from moderation bans: a shared,
  cleared, or copied browser cookie is not durable evidence of a person or IP.
  """

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.BrowserAbuse.Signal
  alias Eirinchan.BrowserIdentity
  alias Eirinchan.Repo

  @default_signal_seconds 3_600

  def record(request, reason, opts \\ []) when is_map(request) do
    repo = Keyword.get(opts, :repo, Repo)
    now = Keyword.get(opts, :now, DateTime.utc_now(:second)) |> DateTime.truncate(:second)
    ttl_seconds = positive_integer(Keyword.get(opts, :ttl_seconds), @default_signal_seconds)

    with browser_ref when is_binary(browser_ref) <- browser_ref(request),
         true <- BrowserIdentity.reference?(browser_ref) do
      attrs = %{
        browser_ref: browser_ref,
        client_key: map_value(request, :client_key),
        reason: normalize_reason(reason),
        expires_at: DateTime.add(now, ttl_seconds, :second)
      }

      conflict_query =
        from signal in Signal,
          where: signal.expires_at < ^attrs.expires_at,
          update: [
            set: [
              client_key: ^attrs.client_key,
              reason: ^attrs.reason,
              expires_at: ^attrs.expires_at,
              updated_at: ^now
            ]
          ]

      %Signal{}
      |> Signal.changeset(attrs)
      |> repo.insert(
        on_conflict: conflict_query,
        conflict_target: :browser_ref,
        allow_stale: true
      )
    else
      _ -> {:ok, :ignored}
    end
  end

  def signaled?(request, opts \\ []) when is_map(request) do
    repo = Keyword.get(opts, :repo, Repo)
    now = Keyword.get(opts, :now, DateTime.utc_now(:second)) |> DateTime.truncate(:second)

    case browser_ref(request) do
      browser_ref when is_binary(browser_ref) ->
        if BrowserIdentity.reference?(browser_ref) do
          repo.exists?(
            from signal in Signal,
              where: signal.browser_ref == ^browser_ref and signal.expires_at > ^now
          )
        else
          false
        end

      _ ->
        false
    end
  end

  def challenge_required?(request, config, opts \\ []) do
    captcha_available?(config) and signaled?(request, opts)
  end

  def captcha_available?(config) do
    captcha = Map.get(config, :captcha, %{})
    provider = Map.get(captcha, :provider, "native")
    expected_response = present?(Map.get(captcha, :expected_response))

    remote_credentials =
      present?(Map.get(captcha, :verify_url)) and present?(Map.get(captcha, :secret))

    Map.get(captcha, :enabled, false) and provider in ["native", "recaptcha", "hcaptcha"] and
      (expected_response or (provider != "native" and remote_credentials))
  end

  def prune_expired(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    now = Keyword.get(opts, :now, DateTime.utc_now(:second)) |> DateTime.truncate(:second)
    {count, _rows} = repo.delete_all(from signal in Signal, where: signal.expires_at <= ^now)
    count
  end

  defp browser_ref(request), do: map_value(request, :browser_ref)

  defp map_value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp normalize_reason(reason) do
    reason
    |> to_string()
    |> String.slice(0, 64)
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default
end
