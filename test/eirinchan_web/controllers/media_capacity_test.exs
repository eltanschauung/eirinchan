defmodule EirinchanWeb.MediaCapacityTest do
  use EirinchanWeb.ConnCase, async: false

  test "busy upload processing returns a retryable response rather than spawning extra work", %{
    conn: conn
  } do
    board = board_fixture()
    upload = upload_fixture("capacity.png", "fixture")

    with_instance_config(%{media_processing_concurrency: 1}, fn ->
      parent = self()

      blocker =
        Task.async(fn ->
          Eirinchan.MediaProcessing.run(fn ->
            send(parent, {:processing, self()})

            receive do
              :finish -> :ok
            end
          end)
        end)

      assert_receive {:processing, worker}

      try do
        response =
          conn
          |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
          |> post("/#{board.uri}/post", %{
            "post" => "New Topic",
            "body" => "fixture body",
            "file" => upload,
            "json_response" => "1"
          })

        assert json_response(response, 503)["error_code"] == "media_busy"
        assert get_resp_header(response, "retry-after") == ["2"]
      after
        send(worker, :finish)
        Task.await(blocker)
      end
    end)
  end
end
