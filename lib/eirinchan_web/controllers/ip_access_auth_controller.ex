defmodule EirinchanWeb.IpAccessAuthController do
  use EirinchanWeb, :controller

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

  def create(conn, %{"password" => password}) do
    config = effective_config()
    ip = RequestMeta.effective_remote_ip(conn)

    with :ok <- IpAccessAuthThrottle.allowed?(ip, config),
         result <- IpAccessAuth.authorize(ip, password, config) do
      handle_authorization(conn, result, config, ip, password)
    else
      {:error, retry_after} when is_integer(retry_after) ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> render_error(config, "Too many attempts. Try again later.", nil, :too_many_requests)
    end
  end

  defp handle_authorization(conn, result, config, ip, password) do
    case result do
      {:ok, _result} ->
        IpAccessAuthThrottle.clear(ip)

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
        render_error(conn, config, "Password is required.", password)

      {:error, :invalid_password} ->
        case IpAccessAuthThrottle.record_failure(ip, config) do
          :ok ->
            render_error(conn, config, "Invalid password.", password)

          {:error, retry_after} ->
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
        render_error(conn, config, "Unable to determine network range.", password)

      {:error, _reason} ->
        render_error(conn, config, "Unable to update access list.", password)
    end
  end

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
