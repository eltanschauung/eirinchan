defmodule EirinchanWeb.ModerationAudit do
  alias Eirinchan.ModerationLog
  alias EirinchanWeb.RequestMeta

  require Logger

  def log(conn, text, opts \\ []) when is_binary(text) do
    moderator = Keyword.get(opts, :moderator, conn.assigns[:current_moderator])

    if moderator do
      attrs = %{
        mod_user_id: moderator.id,
        actor_ip: RequestMeta.effective_remote_ip(conn) |> normalize_ip(),
        board_uri: board_uri(opts),
        text: text
      }

      case ModerationLog.log_action(attrs) do
        {:ok, _entry} ->
          :ok

        {:error, reason} ->
          Logger.error("failed to write moderation log: #{inspect(reason)}")
          :error
      end
    else
      :ok
    end
  end

  defp board_uri(opts) do
    case Keyword.get(opts, :board) || Keyword.get(opts, :board_uri) do
      %{uri: uri} -> uri
      uri when is_binary(uri) -> uri
      _ -> nil
    end
  end

  defp normalize_ip(nil), do: nil
  defp normalize_ip({_, _, _, _} = ip), do: :inet.ntoa(ip) |> to_string()
  defp normalize_ip({_, _, _, _, _, _, _, _} = ip), do: :inet.ntoa(ip) |> to_string()
  defp normalize_ip(ip) when is_binary(ip), do: String.trim(ip)
  defp normalize_ip(_ip), do: nil
end
