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
      html_response?(conn) and
      not excluded_path?(conn.request_path)
  end

  defp html_response?(conn) do
    conn
    |> get_resp_header("content-type")
    |> Enum.any?(&String.starts_with?(&1, "text/html"))
  end

  defp excluded_path?(path) when is_binary(path) do
    String.starts_with?(path, "/manage")
  end

  defp excluded_path?(_path), do: false

  defp etag_value(body) do
    :crypto.hash(:md5, body)
    |> Base.encode16(case: :lower)
  end

  defp document_etag_value(conn, body) do
    case conn.private[:public_document_etag] do
      value when is_binary(value) and value != "" -> value
      _ -> etag_value(body)
    end
  end

  defp if_none_match?(conn, etag) do
    conn
    |> get_req_header("if-none-match")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&String.trim/1)
    |> Enum.any?(fn candidate -> normalize_etag(candidate) == normalize_etag(etag) end)
  end

  defp normalize_etag("W/" <> rest), do: String.trim(rest)
  defp normalize_etag(value), do: String.trim(value)
end
