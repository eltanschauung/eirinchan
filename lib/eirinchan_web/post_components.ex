defmodule EirinchanWeb.PostComponents do
  use Phoenix.Component
  import Phoenix.HTML, only: [raw: 1]
  import Phoenix.HTML.Safe, only: [to_iodata: 1]

  alias EirinchanWeb.{IpPresentation, PostView}

  attr :post, :map, required: true
  attr :config, :map, required: true
  attr :board, :map, required: true
  attr :moderator, :map, default: nil
  attr :own, :boolean, default: false

  def post_identity(assigns) do
    assigns =
      assigns
      |> assign(:visible_ip, visible_ip(assigns.post, assigns.board, assigns.moderator))
      |> assign(:flags, PostView.post_flags(assigns.post, assigns.config))

    ~H"""
    <span :if={@post.subject} class="subject"><%= @post.subject %></span><%= if @post.subject, do: " " %>
    <%= if PostView.email_link?(@post.email, @config) do %>
      <a class="email" href={"mailto:" <> to_string(@post.email)}>
        <span class="name"><%= PostView.display_name(@post, @config) %></span>
      </a>
    <% else %>
      <span class="name"><%= PostView.display_name(@post, @config) %></span>
    <% end %>
    <%= if @own, do: " " %><span :if={@own} class="own_post">(You)</span><%= if @post.tripcode,
      do: " " %><span :if={@post.tripcode} class="trip"><%= @post.tripcode %></span><%= if @visible_ip,
      do: " " %><a
      :if={@visible_ip}
      class="ip-link"
      style="margin:0;"
      href={"/mod.php?/IP/" <> @visible_ip}
    >[<%= @visible_ip %>]</a><%= if @flags != [], do: " " %>
    <%= for {flag, index} <- Enum.with_index(@flags) do %>
      <%= if index > 0, do: " " %>
      <img
        class="flag"
        src={flag.src}
        alt={flag.alt}
        title={flag.alt}
        style={PostView.flag_style(@config)}
      />
    <% end %>
    <%= if @flags != [], do: " " %><time datetime={PostView.iso_timestamp(@post)}><%= PostView.formatted_timestamp(@post) %></time>
    """
  end

  attr :post_id, :integer, required: true
  attr :post_href, :string, required: true
  attr :quote_href, :string, required: true
  attr :quote_mode, :atom, default: :inline
  attr :quote_to, :integer, default: nil
  attr :quick_reply_thread, :integer, default: nil

  def post_number_links(assigns) do
    ~H"""
    &nbsp;<a class="post_no" id={"post_no_#{@post_id}"} onclick={"highlightReply(#{@post_id})"} href={@post_href}>No.</a><a class="post_no" onclick={quote_onclick(@post_id, @quote_mode)} href={@quote_href} data-quote-to={@quote_to} data-quick-reply-thread={@quick_reply_thread}><%= @post_id %></a>
    """
  end

  attr :post_target, :string, required: true

  def reply_post_button(assigns) do
    ~H"""
    <a href="#" class="post-btn" title="Post menu" data-post-target={@post_target}>▶</a>
    """
  end

  attr :post, :map, required: true
  attr :backlinks_map, :map, default: %{}

  def backlinks(assigns) do
    backlinks =
      assigns.post
      |> Map.get(:id)
      |> then(&Map.get(assigns.backlinks_map || %{}, &1, []))

    assigns = assign(assigns, :backlinks, backlinks)

    ~H"""
    <span :if={@backlinks != []} class="mentioned">
      <%= for backlink_id <- @backlinks do %>
        <a
          class={"mentioned-#{backlink_id}"}
          onclick={"highlightReply('#{backlink_id}');"}
          href={"##{backlink_id}"}
        >
          &gt;&gt;<%= backlink_id %>
        </a>
      <% end %>
    </span>
    """
  end

  attr :board_uri, :string, required: true
  attr :thread_id, :integer, required: true
  attr :post_target, :string, required: true
  attr :watch, :map, default: %{watched: false, unread_count: 0}
  attr :show_hide, :boolean, default: false

  def thread_top_controls(assigns) do
    watched = Map.get(assigns.watch || %{}, :watched, false)
    assigns = assign(assigns, :watched, watched)

    ~H"""
    <span class="thread-top-controls">
      <a :if={@show_hide} class="hide-thread-link" href="javascript:void(0)" title="Hide thread">[–]</a>
      <a href="#" class="post-btn" title="Post menu" data-post-target={@post_target}>▶</a>
      <a
        href="javascript:;"
        class={["watch-thread-link", @watched && "watched"]}
        title={if @watched, do: "Unwatch Thread", else: "Watch Thread"}
        data-thread-watch
        data-board-uri={@board_uri}
        data-thread-id={@thread_id}
        data-watch-url={"/watcher/#{@board_uri}/#{@thread_id}"}
        data-unwatch-url={"/watcher/#{@board_uri}/#{@thread_id}"}
        data-watched={to_string(@watched)}
      >
      </a>
    </span>
    """
  end

  attr :moderator, :map, default: nil

  def admin_shortcuts(assigns) do
    ~H"""
    <div :if={@moderator} class="admin-shortcuts unimportant">
      <a href="/manage">Return to Dashboard</a>
      |
      <a href="/manage/logout/browser" onclick="document.getElementById('admin-shortcuts-logout-form').submit(); return false;">Logout</a>
      <form
        id="admin-shortcuts-logout-form"
        action="/manage/logout/browser"
        method="post"
        class="inline-form admin-shortcuts-form"
        hidden
      >
        <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
        <input type="hidden" name="_method" value="delete" />
      </form>
    </div>
    """
  end

  attr :post, :map, required: true
  attr :config, :map, required: true
  attr :op?, :boolean, default: false
  attr :board, :map, default: nil
  attr :moderator, :map, default: nil
  attr :secure_manage_token, :string, default: nil

  def files_block(assigns) do
    ~H"""
    <div class="files">
      <%= for media <- PostView.media_entries(@post, @config) do %>
        <%= if PostView.embed_entry?(media) do %>
          <%= raw(media.embed_html) %>
        <% else %>
          <.file_block
            post={@post}
            file={media}
            config={@config}
            op?={@op?}
            board={@board}
            moderator={@moderator}
            secure_manage_token={@secure_manage_token}
          />
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :post, :map, required: true
  attr :file, :map, required: true
  attr :config, :map, required: true
  attr :op?, :boolean, default: false
  attr :board, :map, default: nil
  attr :moderator, :map, default: nil
  attr :secure_manage_token, :string, default: nil

  def file_block(assigns) do
    ~H"""
    <div
      class={PostView.file_class(@post)}
      {case PostView.multifile_style(@file, @config, multifile: PostView.media_multifile?(@post)) do
        nil -> []
        style -> [style: style]
      end}
    >
      <p class="fileinfo">
        File:
        <a href={@file.file_path}><%= PostView.stored_file_name(@file) %></a>
        <span>
          (<%= PostView.file_size_text(@file) %><%= if PostView.file_dimensions(@file),
            do: raw(", " <> PostView.file_dimensions(@file)) %>, <span
            class="postfilename"
            title={PostView.original_file_name(@file)}
          ><%= PostView.display_file_name(@file, @config) %></span>)
        </span>
        <.file_controls
          post={@post}
          file={@file}
          board={@board}
          moderator={@moderator}
          secure_manage_token={@secure_manage_token}
        />
      </p>
      <.file_image file={@file} config={@config} op?={@op?} />
    </div>
    """
  end

  attr :file, :map, required: true
  attr :config, :map, required: true
  attr :op?, :boolean, default: false

  def file_image(assigns) do
    assigns =
      assigns
      |> assign(:thumb_style, PostView.thumb_style(assigns.file, assigns.config, op?: assigns.op?))
      |> assign(:link_class, PostView.file_link_class(assigns.file))
      |> assign(
        :image_classes,
        ["post-image", if(Map.get(assigns.file, :spoiler, false), do: "spoiler-image", else: nil)]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" ")
      )

    ~H"""
    <a href={@file.file_path} target="_blank" class={@link_class}>
      <img
        class={@image_classes}
        src={PostView.file_thumb_src(@file, @config)}
        loading="lazy"
        decoding="async"
        style={@thumb_style}
        alt=""
      />
    </a>
    """
  end

  attr :post, :map, required: true
  attr :board, :map, default: nil
  attr :moderator, :map, default: nil
  attr :secure_manage_token, :string, default: nil

  def post_controls(assigns) do
    assigns =
      assign(assigns, :controls, PostView.post_controls(assigns.post, assigns.board, assigns.moderator, assigns.secure_manage_token))

    ~H"""
    <span :if={@controls != []} class={if is_nil(@post.thread_id), do: "controls op", else: "controls"}>
      <%= for {control, index} <- Enum.with_index(@controls) do %><%= if index > 0, do: raw("&nbsp;") %><.control_link control={control} /><% end %>
    </span>
    """
  end

  attr :post, :map, required: true
  attr :file, :map, required: true
  attr :board, :map, default: nil
  attr :moderator, :map, default: nil
  attr :secure_manage_token, :string, default: nil

  def file_controls(assigns) do
    assigns =
      assign(assigns, :controls, PostView.file_controls(assigns.post, assigns.file, assigns.board, assigns.moderator, assigns.secure_manage_token))

    ~H"""
    <span :if={@controls != []} class="controls">
      <%= for {control, index} <- Enum.with_index(@controls) do %><%= if index > 0, do: raw("&nbsp;") %><.control_link control={control} /><% end %>
    </span>
    """
  end

  attr :control, :map, required: true

  def control_link(assigns) do
    ~H"""
    <a
      title={@control.title}
      href={@control.href}
      onclick={control_onclick(@control)}
    ><%= @control.label %></a>
    """
  end

  attr :page_data, :map, required: true
  attr :board_uri, :string, required: true
  attr :config, :map, required: true

  def board_pages(assigns) do
    assigns =
      assigns
      |> assign(:previous_page, previous_page(assigns.page_data))
      |> assign(:next_page, next_page(assigns.page_data))
      |> assign(:catalog_label, catalog_label(assigns.config))
      |> assign(:show_catalog, Eirinchan.Themes.page_theme_enabled?("catalog"))

    ~H"""
    <div class="pages">
      <%= if @previous_page do %>
        <a href={@previous_page.link}>Previous</a>
      <% else %>
        Previous
      <% end %>
      <%= for page <- @page_data.pages do %>
        <%= if page.num == @page_data.page do %>
          [<a class="selected"><%= page.num %></a>]
        <% else %>
          [<a href={page.link}><%= page.num %></a>]
        <% end %>
      <% end %>
      <%= if @next_page do %>
        <form action={@next_page.link} method="get"><input type="submit" value="Next" /></form>
      <% end %>
      <%= if @show_catalog do %>
        |
        <a href={"/#{@board_uri}/catalog.html"}><%= @catalog_label %></a>
      <% end %>
    </div>
    """
  end

  attr :page_data, :map, required: true

  def catalog_pages(assigns) do
    ~H"""
    <div class="pages">
      <%= for page <- @page_data.pages do %>
        <%= if page.num == @page_data.page do %>
          [<a class="selected"><%= page.num %></a>]
        <% else %>
          [<a href={page.link}><%= page.num %></a>]
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :post, :map, required: true
  attr :board, :map, required: true
  attr :thread, :map, required: true
  attr :config, :map, required: true
  attr :op?, :boolean, default: false
  attr :hide_fileboard, :boolean, default: false
  attr :own_post_ids, :any, default: MapSet.new()
  attr :show_yous, :boolean, default: false

  def body_container(assigns) do
    ~H"""
    <div
      class="body"
      {case body_style_attr(@post, @config, @op?) do
        nil -> []
        style -> [style: style]
      end}
    >
      <%= raw(
        PostView.body_html(@post, @board, @thread, @config,
          own_post_ids: @own_post_ids,
          show_yous: @show_yous
        )
      ) %>
      <span :if={@post.tag} class="tag-line">Tag: <%= if is_map(@config.allowed_tags),
        do: Map.get(@config.allowed_tags, @post.tag, @post.tag),
        else: @post.tag %></span>
      <span
        :if={@config.fileboard && PostView.show_fileboard_summary?(@post)}
        class="tag-line"
        style={if @hide_fileboard, do: "display:none", else: nil}
      >Fileboard: <%= PostView.fileboard_summary(@post) %></span>
    </div>
    """
  end

  attr :post, :map, required: true
  attr :board, :map, required: true
  attr :thread, :map, required: true
  attr :config, :map, required: true
  attr :moderator, :map, default: nil
  attr :secure_manage_token, :string, default: nil
  attr :backlinks_map, :map, default: %{}
  attr :own_post_ids, :any, default: MapSet.new()
  attr :show_yous, :boolean, default: false
  attr :mobile_client?, :boolean, default: false

  def reply(assigns) do
    ~H"""
    <div class="post reply" id={"reply_#{@post.id}"}>
      <p class="intro">
        <a id={to_string(@post.id)} class="post_anchor"></a>
        <input
          :if={!@mobile_client?}
          type="checkbox"
          class="delete"
          name={"delete_#{@post.id}"}
          id={"delete_#{@post.id}"}
          value={@post.id}
          data-post-select=""
        />
        <.reply_post_button post_target={"reply_#{@post.id}"} />
        <label for={"delete_#{@post.id}"}>
          <.post_identity
            post={@post}
            config={@config}
            board={@board}
            moderator={@moderator}
            own={@show_yous and MapSet.member?(@own_post_ids, @post.id)}
          />
        </label>
        <.post_number_links
          post_id={@post.id}
          post_href={PostView.thread_path(@board, @thread, @config) <> "##{@post.id}"}
          quote_href={PostView.reply_path(@board, @thread, @post, @config, :quote)}
          quote_to={@post.id}
        />
        <.backlinks post={@post} backlinks_map={@backlinks_map} />
      </p>
      <.files_block
        post={@post}
        config={@config}
        board={@board}
        moderator={@moderator}
        secure_manage_token={@secure_manage_token}
      />
      <.post_controls
        post={@post}
        board={@board}
        moderator={@moderator}
        secure_manage_token={@secure_manage_token}
      />
      <.body_container
        post={@post}
        board={@board}
        thread={@thread}
        config={@config}
        own_post_ids={@own_post_ids}
        show_yous={@show_yous}
      />
    </div>
    <br class="clear" />
    """
  end

  def reply_html(assigns), do: assigns |> reply() |> to_iodata() |> IO.iodata_to_binary()

  defp previous_page(page_data) do
    if page_data.page > 1, do: Enum.at(page_data.pages, page_data.page - 2), else: nil
  end

  defp next_page(page_data) do
    if page_data.page < page_data.total_pages, do: Enum.at(page_data.pages, page_data.page), else: nil
  end

  defp catalog_label(config) do
    config
    |> Map.get(:catalog_name, "Catalog")
    |> to_string()
    |> String.trim()
    |> case do
      "" -> "Catalog"
      value -> value
    end
  end

  defp quote_onclick(post_id, :navigate), do: "citeReply(#{post_id})"
  defp quote_onclick(post_id, _mode), do: "return citeReply(#{post_id}, false)"

  defp visible_ip(post, board, moderator) do
    if PostView.can_view_ip?(moderator, board) and post.ip_subnet do
      IpPresentation.display_ip(post.ip_subnet, moderator)
    end
  end

  defp body_style_attr(post, config, _op?) do
    if length(PostView.media_entries(post, config)) > 1, do: "clear:both", else: nil
  end

  defp control_onclick(%{kind: :confirm, confirm: message, secure: secure_href}) do
    escaped_message =
      message
      |> to_string()
      |> String.replace("\\", "\\\\")
      |> String.replace("'", "\\'")

    "if (event.which==2) return true;if (confirm('#{escaped_message}')) document.location='#{secure_href}';return false;"
  end

  defp control_onclick(_control), do: nil
end
