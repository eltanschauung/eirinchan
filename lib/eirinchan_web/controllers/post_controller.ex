defmodule EirinchanWeb.PostController do
  use EirinchanWeb, :controller

  require Logger

  alias Eirinchan.Bans
  alias Eirinchan.LogSystem
  alias Eirinchan.Posts
  alias Eirinchan.Reports
  alias Eirinchan.ThreadPaths
  alias EirinchanWeb.PostView
  alias EirinchanWeb.RequestMeta

  plug EirinchanWeb.Plugs.LoadBoard

  def create(conn, params) do
    params = normalize_legacy_params(params)
    board = conn.assigns.current_board
    config = conn.assigns.current_board_config

    request = %{referer: List.first(get_req_header(conn, "referer"))}

    request =
      Map.merge(request, %{
        remote_ip: RequestMeta.effective_remote_ip(conn),
        forwarded_for: RequestMeta.forwarded_for(conn),
        moderator: conn.assigns[:current_moderator]
      })

    case branch(params) do
      :report ->
        case Reports.create_report(board, params, remote_ip: RequestMeta.effective_remote_ip(conn)) do
          {:ok, report} ->
            respond_reported(conn, board, report, params)

          {:error, reason} when is_atom(reason) ->
            respond_error(
              conn,
              reason,
              error_status(reason),
              error_message(reason, config),
              config
            )

          {:error, %Ecto.Changeset{} = changeset} ->
            respond_changeset_error(conn, changeset)
        end

      :delete ->
        delete_file_only = delete_file_only?(params)

        delete_action =
          if delete_file_only?(params) do
            Posts.delete_post_files(board, params["delete_post_id"], config: config)
          else
            Posts.delete_post(board, params["delete_post_id"], params["password"], config: config)
          end

        case delete_action do
          {:ok, result} when delete_file_only ->
            respond_deleted_file(conn, board, result, params)

          {:ok, result} ->
            respond_deleted(conn, board, result, params)

          {:error, reason} when is_atom(reason) ->
            respond_error(
              conn,
              reason,
              error_status(reason),
              error_message(reason, config),
              config
            )

          {:error, %Ecto.Changeset{} = changeset} ->
            respond_changeset_error(conn, changeset)
        end

      :appeal ->
        case Bans.create_appeal(params["appeal_ban_id"] || params["ban_id"], params) do
          {:ok, appeal} ->
            respond_appealed(conn, board, appeal, params)

          {:error, :not_found} ->
            respond_error(conn, :ban_not_found, :not_found, "Ban not found", config)

          {:error, %Ecto.Changeset{} = changeset} ->
            respond_changeset_error(conn, changeset)
        end

      :post ->
        case Posts.create_post(board, params, config: config, request: request) do
          {:ok, post, meta} ->
            respond_created(conn, board, post, params, meta)

          {:error, reason} when is_atom(reason) ->
            respond_error(
              conn,
              reason,
              error_status(reason),
              error_message(reason, config),
              config
            )

          {:error, %Ecto.Changeset{} = changeset} ->
            respond_changeset_error(conn, changeset)
        end
    end
  end

  defp respond_created(conn, board, post, params, meta) do
    thread_id = post.thread_id || post.id
    config = conn.assigns.current_board_config
    conn = put_post_success_cookie(conn, board, post)
    op? = is_nil(post.thread_id)

    redirect_path =
      cond do
        op? ->
          thread_redirect_path(board, post, thread_id, config)

        meta.noko ->
          suffix = if post.thread_id, do: "#p#{post.id}", else: ""
          "#{thread_redirect_path(board, post, thread_id, config)}#{suffix}"

        true ->
          "/#{board.uri}"
      end

    if params["json_response"] == "1" do
      payload = %{
        id: post.id,
        thread_id: thread_id,
        redirect: redirect_path,
        noko: meta.noko
      }

      payload =
        if post.thread_id do
          case Posts.get_thread(board, thread_id) do
            {:ok, [thread | _]} ->
              Map.put(
                payload,
                :html,
                PostView.reply_html(
                  post,
                  board,
                  thread,
                  config,
                  conn.assigns[:current_moderator],
                  conn.assigns[:secure_manage_token]
                )
              )

            _ ->
              payload
          end
        else
          payload
        end

      json(conn, payload)
    else
      redirect(conn, to: redirect_path)
    end
  end

  defp respond_deleted_file(conn, board, post, params) do
    config = conn.assigns.current_board_config
    thread_id = post.thread_id || post.id
    redirect_path = thread_redirect_or_board(board, thread_id, params, config)

    if params["json_response"] == "1" do
      json(conn, %{
        deleted_post_id: post.id,
        thread_id: thread_id,
        thread_deleted: false,
        file_deleted_only: true,
        redirect: redirect_path
      })
    else
      redirect(conn, to: redirect_path)
    end
  end

  defp thread_redirect_path(board, %{thread_id: nil} = thread, _thread_id, config) do
    ThreadPaths.thread_path(board, thread, config)
  end

  defp thread_redirect_path(board, _post, thread_id, config) do
    case Posts.get_thread(board, thread_id) do
      {:ok, [thread | _]} -> ThreadPaths.thread_path(board, thread, config)
      {:error, :not_found} -> "/#{board.uri}/res/#{thread_id}.html"
    end
  end

  defp respond_error(conn, reason, status, message, config) do
    log_post_error(reason, status, conn)

    if conn.params["json_response"] == "1" do
      payload =
        %{
          error: message,
          error_code: Atom.to_string(reason)
        }
        |> maybe_put_captcha_refresh(reason, config)

      conn
      |> put_status(status)
      |> json(payload)
    else
      conn
      |> put_status(status)
      |> text(message)
    end
  end

  defp respond_changeset_error(conn, changeset) do
    LogSystem.log(
      :warning,
      "post.changeset_error",
      "post.changeset_error",
      %{errors: inspect(changeset.errors), board: conn.assigns.current_board.uri},
      conn.assigns.current_board_config
    )

    respond_error(
      conn,
      :changeset,
      :unprocessable_entity,
      error_message(changeset),
      conn.assigns.current_board_config
    )
  end

  defp respond_reported(conn, board, report, params) do
    redirect_path =
      thread_redirect_or_board(board, report.thread_id, params, conn.assigns.current_board_config)

    if params["json_response"] == "1" do
      json(conn, %{report_id: report.id, redirect: redirect_path, status: "ok"})
    else
      redirect(conn, to: redirect_path)
    end
  end

  defp respond_appealed(conn, board, appeal, params) do
    redirect_path = "/#{board.uri}"

    if params["json_response"] == "1" do
      json(conn, %{appeal_id: appeal.id, redirect: redirect_path, status: "ok"})
    else
      redirect(conn, to: redirect_path)
    end
  end

  defp respond_deleted(conn, board, result, params) do
    config = conn.assigns.current_board_config

    redirect_path =
      if result.thread_deleted do
        "/#{board.uri}"
      else
        thread_redirect_or_board(board, result.thread_id, params, config)
      end

    if params["json_response"] == "1" do
      json(conn, %{
        deleted_post_id: result.deleted_post_id,
        thread_id: result.thread_id,
        thread_deleted: result.thread_deleted,
        redirect: redirect_path
      })
    else
      redirect(conn, to: redirect_path)
    end
  end

  defp branch(params) do
    cond do
      Map.has_key?(params, "report_post_id") -> :report
      Map.has_key?(params, "delete_post_id") -> :delete
      legacy_action(params) == :report -> :report
      legacy_action(params) == :delete -> :delete
      Map.has_key?(params, "appeal_ban_id") or Map.has_key?(params, "ban_id") -> :appeal
      true -> :post
    end
  end

  defp normalize_legacy_params(params) do
    params
    |> put_legacy_password()
    |> put_legacy_selected_checkbox_id()
    |> put_legacy_action_id()
    |> put_legacy_report_id()
  end

  defp put_legacy_password(%{"password" => password} = params)
       when is_binary(password) and password != "",
       do: params

  defp put_legacy_password(params) do
    case params["pwd"] do
      value when is_binary(value) and value != "" -> Map.put(params, "password", value)
      _ -> params
    end
  end

  defp put_legacy_action_id(params) do
    legacy_id = legacy_selected_post_id(params)

    cond do
      is_nil(legacy_id) ->
        params

      legacy_action(params) == :delete and not Map.has_key?(params, "delete_post_id") ->
        Map.put(params, "delete_post_id", legacy_id)

      true ->
        params
    end
  end

  defp put_legacy_selected_checkbox_id(params) do
    case selected_checkbox_id(params) do
      nil -> params
      id -> Map.put_new(params, "delete[]", id)
    end
  end

  defp put_legacy_report_id(params) do
    legacy_id = legacy_selected_post_id(params)

    cond do
      is_nil(legacy_id) ->
        params

      legacy_action(params) == :report and not Map.has_key?(params, "report_post_id") ->
        Map.put(params, "report_post_id", legacy_id)

      true ->
        params
    end
  end

  defp legacy_action(params) do
    cond do
      Map.has_key?(params, "delete") ->
        :delete

      Map.has_key?(params, "report") ->
        :report

      true ->
        case params["mode"] do
          mode when is_binary(mode) ->
            case String.downcase(String.trim(mode)) do
              "delete" -> :delete
              "report" -> :report
              _ -> nil
            end

          _ ->
            nil
        end
    end
  end

  defp legacy_selected_post_id(params) do
    [
      Map.get(params, "delete_post_id"),
      Map.get(params, "report_post_id"),
      Map.get(params, "delete[]"),
      delete_key_id(params),
      report_key_id(params)
    ]
    |> Enum.find_value(&first_legacy_id/1)
  end

  defp delete_key_id(params) do
    Enum.find_value(params, fn
      {"delete_" <> id, _value} when id != "file" -> id
      _ -> nil
    end)
  end

  defp report_key_id(params) do
    Enum.find_value(params, fn
      {"report_" <> id, _value} -> id
      _ -> nil
    end)
  end

  defp first_legacy_id(nil), do: nil
  defp first_legacy_id(""), do: nil
  defp first_legacy_id(value) when is_binary(value), do: value
  defp first_legacy_id([value | _rest]), do: first_legacy_id(value)

  defp first_legacy_id(%{} = values),
    do: values |> Map.values() |> Enum.find_value(&first_legacy_id/1)

  defp first_legacy_id(_value), do: nil

  defp selected_checkbox_id(params) do
    Enum.find_value(params, fn
      {"delete_" <> id, value} ->
        if truthy_checkbox?(value), do: id, else: nil

      _ ->
        nil
    end)
  end

  defp truthy_checkbox?(value) when value in ["on", "1", 1, true], do: true
  defp truthy_checkbox?(_value), do: false

  defp delete_file_only?(params), do: truthy_checkbox?(params["file"])

  defp thread_redirect_or_board(board, nil, _params, _config), do: "/#{board.uri}"

  defp thread_redirect_or_board(board, thread_id, params, config) do
    if params["report_page"] == "board" do
      "/#{board.uri}"
    else
      case Posts.get_thread(board, thread_id) do
        {:ok, [thread | _]} -> ThreadPaths.thread_path(board, thread, config)
        {:error, :not_found} -> "/#{board.uri}/res/#{thread_id}.html"
      end
    end
  end

  defp error_status(:thread_not_found), do: :not_found
  defp error_status(:post_not_found), do: :not_found
  defp error_status(:ban_not_found), do: :not_found
  defp error_status(:dnsbl), do: :forbidden
  defp error_status(:invalid_password), do: :forbidden
  defp error_status(:banned), do: :forbidden
  defp error_status(:thread_locked), do: :forbidden
  defp error_status(:invalid_referer), do: :forbidden
  defp error_status(:antispam), do: :unprocessable_entity
  defp error_status(:invalid_captcha), do: :unprocessable_entity
  defp error_status(:invalid_embed), do: :unprocessable_entity
  defp error_status(:invalid_post_mode), do: :forbidden
  defp error_status(:board_locked), do: :forbidden
  defp error_status(:body_too_long), do: :unprocessable_entity
  defp error_status(:too_many_lines), do: :unprocessable_entity
  defp error_status(:invalid_user_flag), do: :unprocessable_entity
  defp error_status(:reply_hard_limit), do: :unprocessable_entity
  defp error_status(:image_hard_limit), do: :unprocessable_entity
  defp error_status(:invalid_image), do: :unprocessable_entity
  defp error_status(:image_too_large), do: :unprocessable_entity
  defp error_status(:duplicate_file), do: :unprocessable_entity
  defp error_status(:body_required), do: :unprocessable_entity
  defp error_status(:file_required), do: :unprocessable_entity
  defp error_status(:invalid_file_type), do: :unprocessable_entity
  defp error_status(:file_too_large), do: :unprocessable_entity
  defp error_status(:access_list), do: :forbidden
  defp error_status(:upload_failed), do: :internal_server_error
  defp error_status(:changeset), do: :unprocessable_entity

  defp error_message(:thread_not_found, _config), do: "Thread not found"
  defp error_message(:post_not_found, _config), do: "Post not found"
  defp error_message(:dnsbl, config), do: String.replace(config.error.dnsbl, "%s", "DNSBL")
  defp error_message(:invalid_password, config), do: config.error.password
  defp error_message(:banned, config), do: config.error.banned
  defp error_message(:thread_locked, config), do: config.error.locked
  defp error_message(:invalid_referer, config), do: config.error.referer
  defp error_message(:antispam, config), do: config.error.antispam
  defp error_message(:invalid_captcha, config), do: config.error.captcha
  defp error_message(:invalid_embed, config), do: config.error.invalid_embed
  defp error_message(:invalid_post_mode, config), do: config.error.bot
  defp error_message(:board_locked, config), do: config.error.board_locked
  defp error_message(:body_too_long, config), do: config.error.toolong_body
  defp error_message(:too_many_lines, config), do: config.error.toomanylines
  defp error_message(:invalid_user_flag, config), do: config.error.invalid_flag
  defp error_message(:reply_hard_limit, config), do: config.error.reply_hard_limit
  defp error_message(:image_hard_limit, config), do: config.error.image_hard_limit
  defp error_message(:invalid_image, config), do: config.error.invalid_image
  defp error_message(:image_too_large, config), do: config.error.image_too_large
  defp error_message(:duplicate_file, config), do: config.error.duplicate_file
  defp error_message(:body_required, config), do: config.error.tooshort_body
  defp error_message(:file_required, config), do: config.error.file_required
  defp error_message(:invalid_file_type, config), do: config.error.filetype
  defp error_message(:file_too_large, config), do: config.error.file_too_large
  defp error_message(:access_list, _config), do: "IP not permitted for multi-file OP posting."
  defp error_message(:upload_failed, config), do: config.error.upload_failed
  defp error_message(:ban_not_found, _config), do: "Ban not found"
  defp error_message(:changeset, _config), do: "Request invalid"

  defp error_message(changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {message, _opts}} ->
      "#{field} #{message}"
    end)
  end

  defp maybe_put_captcha_refresh(payload, :invalid_captcha, config) do
    captcha = config.captcha || %{}

    if captcha.refresh_on_error do
      Map.merge(payload, %{
        refresh_captcha: true,
        captcha_provider: captcha.provider,
        captcha_field: captcha_field(captcha.provider),
        captcha_challenge: captcha.challenge,
        captcha_refresh_token: Integer.to_string(System.unique_integer([:positive]))
      })
    else
      payload
    end
  end

  defp maybe_put_captcha_refresh(payload, _reason, _config), do: payload

  defp captcha_field("native"), do: "captcha"
  defp captcha_field("recaptcha"), do: "g-recaptcha-response"
  defp captcha_field("hcaptcha"), do: "h-captcha-response"
  defp captcha_field(_provider), do: "captcha"

  defp put_post_success_cookie(conn, _board, _post) do
    referer =
      conn
      |> get_req_header("referer")
      |> List.first()

    if is_binary(referer) and referer != "" do
      successful =
        conn.req_cookies
        |> Map.get("eirinchan_posted")
        |> decode_post_success_cookie()
        |> Map.put(referer, true)

      put_resp_cookie(
        conn,
        "eirinchan_posted",
        Jason.encode!(successful),
        max_age: 120,
        path: "/"
      )
    else
      conn
    end
  end

  defp decode_post_success_cookie(raw_cookie) when is_binary(raw_cookie) do
    case Jason.decode(raw_cookie) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _ -> %{}
    end
  end

  defp decode_post_success_cookie(_raw_cookie) do
    %{}
  end

  defp log_post_error(reason, status, conn) do
    level =
      if status in [:internal_server_error] do
        :error
      else
        :warning
      end

    metadata = %{
      reason: reason,
      status: Plug.Conn.Status.code(status),
      board: conn.assigns.current_board.uri,
      request_id: Logger.metadata()[:request_id],
      remote_ip: RequestMeta.effective_remote_ip(conn)
    }

    LogSystem.log(
      level,
      "post.error",
      "post.error",
      metadata,
      conn.assigns.current_board_config
    )

    write_post_failure_log(conn, metadata)
  end

  defp write_post_failure_log(conn, metadata) do
    log_path = Path.expand("../../../var/post_failures.log", __DIR__)

    line =
      %{
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
        board: conn.assigns.current_board.uri,
        request_id: metadata.request_id,
        status: metadata.status,
        reason: metadata.reason,
        method: conn.method,
        request_path: conn.request_path,
        query_string: conn.query_string,
        host: conn.host,
        port: conn.port,
        scheme: Atom.to_string(conn.scheme),
        remote_ip: inspect(metadata.remote_ip),
        effective_remote_ip: inspect(RequestMeta.effective_remote_ip(conn)),
        forwarded_for: inspect(RequestMeta.forwarded_for(conn)),
        referer: List.first(get_req_header(conn, "referer")),
        origin: List.first(get_req_header(conn, "origin")),
        user_agent: List.first(get_req_header(conn, "user-agent")),
        params: sanitize_failure_params(conn.params)
      }
      |> Jason.encode!()
      |> Kernel.<>("\n")

    log_path
    |> Path.dirname()
    |> File.mkdir_p!()

    _ = File.write(log_path, line, [:append])
    :ok
  end

  defp sanitize_failure_params(params) when is_map(params) do
    Map.new(params, fn {key, value} -> {key, sanitize_failure_param(key, value)} end)
  end

  defp sanitize_failure_params(other), do: inspect(other)

  defp sanitize_failure_param(key, _value)
       when key in [
              "_csrf_token",
              "password",
              "pwd",
              "captcha",
              "g-recaptcha-response",
              "h-captcha-response",
              "hash",
              "antispam_answer"
            ],
       do: "[REDACTED]"

  defp sanitize_failure_param(_key, %Plug.Upload{filename: filename, content_type: content_type}) do
    %{filename: filename, content_type: content_type}
  end

  defp sanitize_failure_param(_key, value) when is_map(value), do: sanitize_failure_params(value)

  defp sanitize_failure_param(key, value) when is_list(value) do
    cond do
      key in ["files", "files[]"] ->
        Enum.map(value, &sanitize_failure_param(key, &1))

      true ->
        Enum.map(value, &sanitize_failure_param(key, &1))
    end
  end

  defp sanitize_failure_param(_key, value), do: value
end
