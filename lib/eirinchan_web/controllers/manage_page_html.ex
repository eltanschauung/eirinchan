defmodule EirinchanWeb.ManagePageHTML do
  use EirinchanWeb, :html
  import EirinchanWeb.BrowserPostComponents

  alias Eirinchan.Noticeboard.Entry, as: NoticeboardEntry
  alias EirinchanWeb.PostView

  embed_templates "manage_page_html/*"

  attr :post, :map, required: true
  attr :board, :map, required: true
  attr :thread, :map, required: true
  attr :config, :map, required: true
  attr :moderator, :map, default: nil
  attr :secure_manage_token, :string, default: nil
  attr :backlinks_map, :map, default: %{}
  attr :own_post_ids, :any, default: MapSet.new()
  attr :show_yous, :boolean, default: false

  def moderation_post(assigns) do
    ~H"""
    <.browser_post
      post={@post}
      board={@board}
      thread={@thread}
      config={@config}
      moderator={@moderator}
      secure_manage_token={@secure_manage_token}
      backlinks_map={@backlinks_map}
      own_post_ids={@own_post_ids}
      show_yous={@show_yous}
      show_selection={true}
      show_post_button={!is_nil(@post.thread_id)}
      show_post_controls={true}
      show_reply_link={true}
      quote_mode={:navigate}
    />
    """
  end

  def noticeboard_delete_token(%NoticeboardEntry{id: id}) do
    Phoenix.Token.sign(EirinchanWeb.Endpoint, "noticeboard-delete", Integer.to_string(id))
  end

  def noticeboard_page_path(1), do: "/manage/noticeboard"
  def noticeboard_page_path(page_no) when is_integer(page_no) and page_no > 1, do: "/manage/noticeboard/#{page_no}"
end
