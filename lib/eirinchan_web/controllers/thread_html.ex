defmodule EirinchanWeb.ThreadHTML do
  use EirinchanWeb, :html

  alias Eirinchan.Posts
  alias EirinchanWeb.PostView

  def captcha_enabled?(config, browser_challenge? \\ false),
    do: browser_challenge? or Posts.captcha_required?(config, false)

  embed_templates "thread_html/*"
end
