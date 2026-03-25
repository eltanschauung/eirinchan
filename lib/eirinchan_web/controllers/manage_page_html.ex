defmodule EirinchanWeb.ManagePageHTML do
  use EirinchanWeb, :html
  import EirinchanWeb.BrowserPostComponents
  import EirinchanWeb.BrowserPageComponents

  alias Eirinchan.Noticeboard.Entry, as: NoticeboardEntry
  alias Eirinchan.Moderation.ModUser
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
  attr :preferred_thread_path, :string, default: nil

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
      preferred_thread_path={@preferred_thread_path}
      quote_mode={:navigate}
    />
    """
  end

  def noticeboard_delete_token(%NoticeboardEntry{id: id}) do
    Phoenix.Token.sign(EirinchanWeb.Endpoint, "noticeboard-delete", Integer.to_string(id))
  end

  def noticeboard_page_path(1), do: "/manage/noticeboard"
  def noticeboard_page_path(page_no) when is_integer(page_no) and page_no > 1, do: "/manage/noticeboard/#{page_no}"

  def custom_page_path(%{slug: slug}), do: custom_page_path(slug)
  def custom_page_path("faq"), do: "/faq"
  def custom_page_path("flags"), do: "/flags"
  def custom_page_path("formatting"), do: "/formatting"
  def custom_page_path("rules"), do: "/rules"
  def custom_page_path(slug) when is_binary(slug), do: "/pages/#{slug}"

  def mod_role_label(%ModUser{role: role}), do: mod_role_label(role)
  def mod_role_label("admin"), do: "Administrator"
  def mod_role_label("mod"), do: "Moderator"
  def mod_role_label("janitor"), do: "Janitor"
  def mod_role_label(_role), do: "Unknown"

  def user_board_labels(%ModUser{role: "admin"}), do: ["all boards"]
  def user_board_labels(%ModUser{all_boards: true}), do: ["all boards"]

  def user_board_labels(%ModUser{board_accesses: accesses}) when is_list(accesses) do
    accesses
    |> Enum.map(fn access -> access.board && access.board.uri end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()
  end

  def user_board_labels(_user), do: []
end
