defmodule EirinchanWeb.Plugs.RequirePageTheme do
  @moduledoc false

  alias Eirinchan.Themes
  alias EirinchanWeb.ErrorPages

  def init(opts), do: opts

  def call(conn, opts) do
    theme = Keyword.fetch!(opts, :theme)

    if Themes.page_theme_enabled?(theme) do
      conn
    else
      ErrorPages.not_found(conn)
    end
  end
end
