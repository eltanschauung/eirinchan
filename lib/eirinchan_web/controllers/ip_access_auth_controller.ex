defmodule EirinchanWeb.IpAccessAuthController do
  use EirinchanWeb, :controller

  alias Eirinchan.IpAccessAuth
  alias Eirinchan.Settings
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
      asset_version: conn.assigns[:asset_version]
    )
  end

  def create(conn, %{"password" => password}) do
    config = effective_config()
    ip = RequestMeta.effective_remote_ip(conn)

    case IpAccessAuth.authorize(ip, password, config) do
      {:ok, _result} ->
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
          asset_version: conn.assigns[:asset_version]
        )

      {:error, :password_required} ->
        render_error(conn, config, "Password is required.", password)

      {:error, :invalid_password} ->
        render_error(conn, config, "Invalid password.", password)

      {:error, :invalid_ip} ->
        render_error(conn, config, "Unable to determine network range.", password)

      {:error, _reason} ->
        render_error(conn, config, "Unable to update access list.", password)
    end
  end

  defp render_error(conn, config, message, password) do
    conn
    |> put_status(:unprocessable_entity)
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
      asset_version: conn.assigns[:asset_version]
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
      value when is_binary(value) and value != "" -> value
      _ -> "/"
    end
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
