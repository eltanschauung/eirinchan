defmodule EirinchanWeb.Plugs.PublicDocumentCache do
  @moduledoc false

  import Plug.Conn

  @cache_control "private, no-cache"

  def init(opts), do: opts

  def call(conn, _opts) do
    register_before_send(conn, &apply_document_cache/1)
  end

  defp apply_document_cache(conn) do
    if cacheable_document?(conn) do
      body = IO.iodata_to_binary(conn.resp_body || "")
      etag = ~s("#{document_etag_value(conn, body)}")

      conn =
        conn
        |> put_resp_header("etag", etag)
        |> put_resp_header("cache-control", @cache_control)

      if if_none_match?(conn, etag) do
        conn
        |> resp(:not_modified, "")
        |> delete_resp_header("content-length")
      else
        conn
      end
    else
      conn
    end
  end

  defp cacheable_document?(conn) do
    conn.method == "GET" and
      conn.status == 200 and
      cacheable_content_type?(conn) and
      not excluded_path?(conn.request_path)
  end

  defp cacheable_content_type?(conn) do
    conn
    |> get_resp_header("content-type")
    |> Enum.any?(fn type ->
      Enum.any?(
        ["text/html", "application/xml", "application/rss+xml"],
        &String.starts_with?(type, &1)
      )
    end)
  end

  # The feedback document embeds a session-bound CSRF token in a plain HTML
  # form. Revalidating it by its content-only ETag can pair a cached form from
  # an old session with a newly issued session cookie, making the submission
  # fail CSRF validation.
  defp excluded_path?("/feedback"), do: true

  defp excluded_path?(path) when is_binary(path) do
    String.starts_with?(path, "/manage")
  end

  defp excluded_path?(_path), do: false

  defp etag_value(body) do
    :crypto.hash(:sha256, body)
    |> Base.encode16(case: :lower)
  end

  defp document_etag_value(conn, body) do
    # The updater's fragment validator is part of its existing protocol. A
    # full document must instead identify the complete rendered representation,
    # including its session-bound forms and personalized root layout.
    case conn.private[:public_fragment_etag] do
      value when is_binary(value) and value != "" -> value
      _ -> etag_value(body)
    end
  end

  defp if_none_match?(conn, etag) do
    conn
    |> get_req_header("if-none-match")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&String.trim/1)
    |> Enum.any?(fn candidate ->
      candidate == "*" or normalize_etag(candidate) == normalize_etag(etag)
    end)
  end

  defp normalize_etag("W/" <> rest), do: String.trim(rest)
  defp normalize_etag(value), do: String.trim(value)
end
