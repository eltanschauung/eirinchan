defmodule EirinchanWeb.Plugs.PublicDocumentCacheTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test
  alias EirinchanWeb.Plugs.PublicDocumentCache

  test "a fragment hash cannot validate two different complete documents" do
    first = document("<html>first shell</html>")
    [etag] = get_resp_header(first, "etag")
    second = document("<html>different shell</html>", etag)
    assert second.status == 200
    assert second.resp_body == "<html>different shell</html>"
    refute get_resp_header(second, "etag") == [etag]
  end

  test "byte-identical documents still honor conditional requests" do
    first = document("<html>stable</html>")
    [etag] = get_resp_header(first, "etag")
    second = document("<html>stable</html>", etag)
    assert second.status == 304
    assert second.resp_body == ""
  end

  test "a wildcard conditional request recognizes an existing document" do
    assert document("<html>stable</html>", "*").status == 304
  end

  defp document(body, etag \\ nil) do
    conn = conn(:get, "/example")
    conn = if etag, do: put_req_header(conn, "if-none-match", etag), else: conn

    conn
    |> put_private(:public_document_etag, "unchanged-fragment")
    |> PublicDocumentCache.call([])
    |> put_resp_content_type("text/html")
    |> send_resp(200, body)
  end
end
