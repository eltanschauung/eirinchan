defmodule EirinchanWeb.PollController do
  use EirinchanWeb, :controller
  alias Eirinchan.Polls
  alias EirinchanWeb.RequestMeta

  plug :private_response
  plug EirinchanWeb.Plugs.RequireCsrfToken when action in [:vote]

  def state(conn, %{"ids" => ids}) when is_binary(ids) and byte_size(ids) <= 1_100 do
    with parts when length(parts) in 1..50 <- String.split(ids, ","),
         parsed <- Enum.map(parts, &parse_id/1),
         true <- Enum.all?(parsed, &is_integer/1) do
      reply(conn, 200, %{data: Polls.states(Enum.uniq(parsed), RequestMeta.public_identity(conn))})
    else
      _ -> reply(conn, 400, %{error: "Supply between 1 and 50 valid poll IDs."})
    end
  end

  def state(conn, _), do: reply(conn, 400, %{error: "Supply between 1 and 50 valid poll IDs."})

  def vote(conn, %{"post_id" => id, "choice" => choice}) do
    with post_id when is_integer(post_id) <- parse_id(id),
         choice when is_integer(choice) <- parse_choice(choice),
         {:ok, state} <- Polls.vote(post_id, choice, RequestMeta.public_identity(conn)) do
      reply(conn, 200, %{data: state})
    else
      {:error, :not_found} ->
        reply(conn, 404, %{error: "Poll not found."})

      {:error, :rate_limited} ->
        conn
        |> put_resp_header("retry-after", "60")
        |> reply(429, %{error: "Too many votes. Please try again shortly."})

      _ ->
        reply(conn, 422, %{error: "Choose one valid poll option."})
    end
  end

  def vote(conn, _), do: reply(conn, 422, %{error: "Choose one valid poll option."})

  defp parse_id(id) when is_binary(id) and byte_size(id) in 1..19 do
    case Integer.parse(id) do
      {value, ""} when value > 0 and value <= 9_223_372_036_854_775_807 -> value
      _ -> nil
    end
  end

  defp parse_id(_), do: nil

  defp parse_choice(value) when is_integer(value) and value in 0..5, do: value

  defp parse_choice(value) when is_binary(value) and byte_size(value) == 1 do
    case Integer.parse(value) do
      {choice, ""} when choice in 0..5 -> choice
      _ -> nil
    end
  end

  defp parse_choice(_), do: nil

  defp reply(conn, status, payload) do
    conn
    |> put_status(status)
    |> json(payload)
  end

  defp private_response(conn, _opts) do
    conn
    |> put_resp_header("cache-control", "private, no-store")
    |> put_resp_header("vary", "Cookie")
  end
end
