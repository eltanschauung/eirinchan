defmodule EirinchanWeb.IpAccessAuthController do
  use EirinchanWeb, :controller

  alias Eirinchan.EventLog
  alias Eirinchan.IpAccessAuth
  alias Eirinchan.IpAccessAuthThrottle
  alias Eirinchan.Settings
  alias Eirinchan.SiteContact
  alias EirinchanWeb.RequestMeta
  alias EirinchanWeb.ThemeRegistry

  def show(conn, _params) do
    config = effective_config()

    conn
    |> put_root_layout(false)
    |> render(:show,
      layout: false,
      title: config.title,
      message: config.message,
      auth_path: request_path(conn, config),
      redirect_url: redirect_url(conn),
      error: nil,
      success: false,
      entered_password: nil,
      theme_stylesheet: theme_stylesheet(config, conn),
      asset_version: conn.assigns[:asset_version],
      contact_email: SiteContact.email()
    )
  end

  def create(conn, params) do
    password = submitted_password(params)
    config = effective_config()
    ip = RequestMeta.effective_remote_ip(conn)

    with :ok <- IpAccessAuthThrottle.allowed?(ip, config),
         result <- IpAccessAuth.authorize(ip, password, config) do
      handle_authorization(conn, result, config, ip, password)
    else
      {:error, retry_after} when is_integer(retry_after) ->
        log_attempt(conn, "auth.ip_access.rejected", "rate_limited", password)

        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> render_error(config, "Too many attempts. Try again later.", nil, :too_many_requests)
    end
  end

  defp handle_authorization(conn, result, config, ip, password) do
    case result do
      {:ok, _result} ->
        IpAccessAuthThrottle.clear(ip)
        log_attempt(conn, "auth.ip_access.granted", "granted", password, :info)

        conn
        |> put_root_layout(false)
        |> render(:show,
          layout: false,
          title: config.title,
          message: config.message,
          auth_path: request_path(conn, config),
          redirect_url: redirect_url(conn),
          error: nil,
          success: true,
          entered_password: nil,
          theme_stylesheet: theme_stylesheet(config, conn),
          asset_version: conn.assigns[:asset_version],
          contact_email: SiteContact.email()
        )

      {:error, :password_required} ->
        log_attempt(conn, "auth.ip_access.rejected", "password_required", password)
        render_error(conn, config, "Password is required.", password)

      {:error, :invalid_password} ->
        case IpAccessAuthThrottle.record_failure(ip, config) do
          :ok ->
            log_attempt(conn, "auth.ip_access.rejected", "invalid_password", password)
            render_error(conn, config, "Invalid password.", password)

          {:error, retry_after} ->
            log_attempt(conn, "auth.ip_access.rejected", "rate_limited", password)

            conn
            |> put_resp_header("retry-after", Integer.to_string(retry_after))
            |> render_error(
              config,
              "Too many attempts. Try again later.",
              nil,
              :too_many_requests
            )
        end

      {:error, :invalid_ip} ->
        log_attempt(conn, "auth.ip_access.failed", "invalid_ip", password, :error)
        render_error(conn, config, "Unable to determine network range.", password)

      {:error, reason} ->
        log_attempt(conn, "auth.ip_access.failed", reason, password, :error)
        render_error(conn, config, "Unable to update access list.", password)
    end
  end

  defp log_attempt(conn, event, outcome, password, level \\ :warning) do
    {ip_subnet, network_id} = network_metadata(conn)

    EventLog.log(
      conn,
      event,
      %{
        browser_id: RequestMeta.browser_ref(conn),
        browser_present: is_binary(RequestMeta.browser_ref(conn)),
        ip_subnet: ip_subnet,
        network_id: network_id,
        outcome: outcome,
        status: if(outcome == "granted", do: "passed", else: "failed"),
        submitted_value: password
      },
      level
    )
  end

  defp network_metadata(conn) do
    conn
    |> RequestMeta.effective_remote_ip()
    |> IpAccessAuth.subnet_for_ip()
    |> case do
      {:ok, subnet} -> {subnet, EventLog.subject_id(subnet, :ip_access_audit_subnet)}
      _error -> {nil, nil}
    end
  end

  defp submitted_password(params) when is_map(params) do
    case Map.get(params, "password") do
      value when is_binary(value) -> value
      _other -> ""
    end
  end

  defp submitted_password(_params), do: ""

  defp render_error(conn, config, message, password, status \\ :unprocessable_entity) do
    conn
    |> put_status(status)
    |> put_root_layout(false)
    |> render(:show,
      layout: false,
      title: config.title,
      message: config.message,
      auth_path: request_path(conn, config),
      redirect_url: redirect_url(conn),
      error: message,
      success: false,
      entered_password: password,
      theme_stylesheet: theme_stylesheet(config, conn),
      asset_version: conn.assigns[:asset_version],
      contact_email: SiteContact.email()
    )
  end

  defp effective_config do
    instance_config = Settings.current_instance_config()

    instance_config
    |> Map.get(:ip_access_auth, %{})
    |> Map.put(:passwords, Map.get(instance_config, :ip_access_passwords, []))
    |> IpAccessAuth.effective_config()
  end

  defp request_path(conn, config) do
    conn.assigns[:ip_access_auth_request_path] || IpAccessAuth.auth_path(config)
  end

  defp redirect_url(conn) do
    case List.first(get_req_header(conn, "referer")) do
      value when is_binary(value) and value != "" -> safe_referer_path(conn, value)
      _ -> "/"
    end
  end

  defp safe_referer_path(conn, value) do
    uri = URI.parse(value)

    cond do
      local_path?(uri, value) ->
        relative_uri(uri)

      same_origin?(conn, uri) ->
        relative_uri(uri)

      true ->
        "/"
    end
  rescue
    _ -> "/"
  end

  defp local_path?(%URI{scheme: nil, host: nil, userinfo: nil}, value) do
    String.starts_with?(value, "/") and
      not String.starts_with?(value, "//") and
      not String.contains?(value, ["\\", "\r", "\n", "\0"])
  end

  defp local_path?(_uri, _value), do: false

  defp same_origin?(conn, %URI{scheme: scheme, host: host, userinfo: nil} = uri)
       when scheme in ["http", "https"] and is_binary(host) do
    String.downcase(host) == String.downcase(conn.host) and
      scheme == Atom.to_string(conn.scheme) and
      effective_port(uri) == effective_port(conn.scheme, conn.port)
  end

  defp same_origin?(_conn, _uri), do: false

  defp effective_port(%URI{scheme: scheme, port: nil}), do: default_port(scheme)
  defp effective_port(%URI{port: port}), do: port

  defp effective_port(scheme, port) when port in [80, 443],
    do: default_port(Atom.to_string(scheme))

  defp effective_port(_scheme, port), do: port

  defp default_port("http"), do: 80
  defp default_port("https"), do: 443
  defp default_port(_scheme), do: nil

  defp relative_uri(uri) do
    path = if is_binary(uri.path) and String.starts_with?(uri.path, "/"), do: uri.path, else: "/"
    URI.to_string(%URI{path: path, query: uri.query, fragment: uri.fragment})
  end

  defp theme_stylesheet(config, conn) do
    theme_name = Map.get(config, :theme)

    cond do
      theme_name in [nil, "", false] ->
        nil

      theme = ThemeRegistry.fetch(theme_name) ->
        theme.stylesheet

      true ->
        conn.assigns[:theme_stylesheet]
    end
  end
end
