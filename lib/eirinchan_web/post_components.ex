defmodule EirinchanWeb.PostComponents do
  use Phoenix.Component
  import Phoenix.HTML, only: [raw: 1]
  import Phoenix.HTML.Safe, only: [to_iodata: 1]

  alias EirinchanWeb.{IpPresentation, PostView}

  attr :groups, :list, required: true
  attr :class_name, :string, default: "boardlist"
  attr :watcher_count, :integer, default: 0
  attr :watcher_you_count, :integer, default: 0
  attr :mobile_client?, :boolean, default: false

  def boardlist(assigns) do
    ~H"""
    <div class={@class_name}>
      <%= for group <- @groups do %>
        <% links = group[:links] || group %>
        <span class="sub" data-description={group[:description]}>
          [
          <%= for {link, index} <- Enum.with_index(links) do %>
            <%= if index > 0, do: " / " %><a href={link.href} title={link.title}><%= link.label %></a>
          <% end %>
          ]
        </span>
        <%= if group != List.last(@groups), do: "  " %>
      <% end %>
      <span id="admin_options_links" style="float: right;">
        <a
          :if={!@mobile_client?}
          id="watcher-link"
          href="javascript:void(0)"
          title={"Watcher#{if @watcher_count > 0, do: " (#{@watcher_count})", else: ""}"}
          aria-label={"Watcher#{if @watcher_count > 0, do: " (#{@watcher_count})", else: ""}"}
          data-count={@watcher_count}
          class={if @watcher_you_count > 0, do: "replies-quoting-you", else: nil}
        >
          👁
        </a>
        <span :if={!@mobile_client?}>&nbsp;</span><a id="admin-link" href="/manage" title="Admin">[Admin]</a><span>&nbsp;</span><a
          id="options-link"
          href="javascript:void(0)"
          title="Options"
        >[Options]</a>
      </span>
    </div>
    """
  end

  attr :theme_options, :list, default: []
  attr :theme_label, :string, default: "Yotsuba"

  def options_shell(assigns) do
    ~H"""
    <div id="options_handler" style="display:none">
      <div id="options_background"></div>
      <div id="options_div">
        <a id="options_close" href="javascript:void(0)"><i class="fa fa-times"></i></a>
        <div id="options_tablist">
          <div id="options-tab-icon-general" class="options_tab_icon">
            <i class="fa fa-home"></i>
            <div>General</div>
          </div>
          <div id="options-tab-icon-watcher" class="options_tab_icon">
            <i class="fa fa-eye"></i>
            <div>Watcher</div>
          </div>
          <div id="options-exit-tab" class="options_tab_icon options_exit_tab">
            <div>Exit</div>
          </div>
        </div>
        <div id="options-tab-general" class="options_tab" style="display:none">
          <h2>General</h2>
          <div id="general-preferences">
            <div :if={@theme_options != []} id="style-select" style="float:none;margin-bottom:0px">
              Style:
              <select onchange="return changeStyle(this.value)">
                <%= for option <- @theme_options do %>
                  <% label = option.label || option.name || "Style" %>
                  <option value={label} selected={label == @theme_label}><%= label %></option>
                <% end %>
              </select>
            </div>
          </div>
          <div id="options-storage-controls">
            <span>Storage: </span>
            <button id="options-storage-export" type="button">Export</button>
            <button id="options-storage-import" type="button">Import</button>
            <button id="options-storage-erase" type="button">Erase</button>
            <input id="options-storage-output" type="text" class="output" hidden />
          </div>
        </div>
        <div id="options-tab-watcher" class="options_tab" style="display:none">
          <h2>Watcher</h2>
          <div id="watcher-tab-content">
            <div class="watcher-loading">Loading...</div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def post_menu_shell(assigns) do
    ~H"""
    <div id="post-menu-root" class="post-menu hidden" hidden></div>
    """
  end

  def boardlist_html(assigns) do
    assigns
    |> with_component_assigns()
    |> boardlist()
    |> to_iodata()
    |> IO.iodata_to_binary()
  end

  def post_identity_html(assigns) do
    assigns
    |> with_component_assigns()
    |> post_identity()
    |> to_iodata()
    |> IO.iodata_to_binary()
  end

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
    <%= if @flags != [], do: " " %><time
      datetime={PostView.iso_timestamp(@post)}
      data-local="true"
      title={PostView.relative_timestamp(@post)}
    ><%= PostView.formatted_timestamp(@post, @config) %></time>
    """
  end

  attr :post_id, :integer, required: true
  attr :post_href, :string, required: true
  attr :quote_href, :string, required: true
  attr :quote_mode, :atom, default: :inline
  attr :quote_to, :integer, default: nil
  attr :quick_reply_thread, :integer, default: nil
  attr :attrs, :global, default: %{}

  def post_number_links(assigns) do
    ~H"""
    &nbsp;<a
      class="post_no"
      id={"post_no_#{@post_id}"}
      onclick={"highlightReply(#{@post_id})"}
      href={@post_href}
    >No.</a>
    <a
      class="post_no"
      onclick={quote_onclick(@post_id, @quote_mode)}
      href={@quote_href}
      data-quote-to={@quote_to}
      data-quick-reply-thread={@quick_reply_thread}
      {@attrs}
    >
      <%= @post_id %>
    </a>
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

  def post_number_links_html(assigns) do
    assigns
    |> with_component_assigns()
    |> post_number_links()
    |> to_iodata()
    |> IO.iodata_to_binary()
  end

  def backlinks_html(assigns) do
    assigns
    |> with_component_assigns()
    |> backlinks()
    |> to_iodata()
    |> IO.iodata_to_binary()
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
      <a :if={@show_hide} class="hide-thread-link" href="javascript:void(0)" title="Hide thread">
        [–]
      </a>
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
      <a
        href="/manage/logout/browser"
        onclick="document.getElementById('admin-shortcuts-logout-form').submit(); return false;"
      >
        Logout
      </a>
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

  def nav_arrows(assigns) do
    ~H"""
    <div
      class="navarrow navarrow-top"
      aria-hidden="true"
      style="position:fixed;bottom:100px;right:20px;cursor:pointer;z-index:50;"
    >
      <a href="#top" title="Scroll to top" aria-label="Scroll to top">
        <img src="/reisen_up.png" alt="Scroll to top" style="width:30px;height:80px;" />
      </a>
    </div>
    <div
      class="navarrow navarrow-bottom"
      aria-hidden="true"
      style="position:fixed;bottom:30px;right:20px;cursor:pointer;z-index:50;"
    >
      <a href="#bottom" title="Scroll to bottom" aria-label="Scroll to bottom">
        <img src="/tewi_down.png" alt="Scroll to bottom" style="width:30px;height:80px;" />
      </a>
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
    media_html =
      assigns.post
      |> PostView.media_entries(assigns.config)
      |> Enum.map(fn media ->
        if PostView.embed_entry?(media) do
          media.embed_html
        else
          file_block_html(%{
            post: assigns.post,
            file: media,
            config: assigns.config,
            op?: assigns.op?,
            board: assigns.board,
            moderator: assigns.moderator,
            secure_manage_token: assigns.secure_manage_token
          })
        end
      end)
      |> IO.iodata_to_binary()

    assigns = assign(assigns, :media_html, media_html)

    ~H"""
    <div class="files"><%= raw(@media_html) %></div>
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
    assigns =
      assigns
      |> assign(:video_file?, PostView.video_file?(assigns.file))
      |> assign(:deleted_file?, PostView.deleted_file?(assigns.file))

    ~H"""
    <div
      class={PostView.file_class(@post)}
      {case PostView.multifile_style(@file, @config, multifile: PostView.media_multifile?(@post)) do
        nil -> []
        style -> [style: style]
      end}
    >
      <p :if={!@deleted_file?} class="fileinfo">
        File: <a href={@file.file_path}><%= PostView.stored_file_name(@file) %></a>
        <span>
          (<%= PostView.file_size_text(@file) %>
          <%= if PostView.file_dimensions(@file) do %>
            , <%= PostView.file_dimensions(@file) %>
          <% end %>, <span class="postfilename" title={PostView.original_file_name(@file)}><%= PostView.display_file_name(@file, @config) %></span>)
        </span>
        <span :if={@video_file?} class="video-loop-controls" data-video-loop-controls>
          <span class="video-loop-control" data-video-loop-mode="once">[play once]</span>
          <span class="video-loop-control active" data-video-loop-mode="loop">[loop]</span>
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

  def file_block_html(assigns) do
    assigns
    |> with_component_assigns()
    |> file_block()
    |> to_iodata()
    |> IO.iodata_to_binary()
  end

  attr :file, :map, required: true
  attr :config, :map, required: true
  attr :op?, :boolean, default: false

  def file_image(assigns) do
    assigns =
      assigns
      |> assign(
        :thumb_style,
        PostView.thumb_style(assigns.file, assigns.config, op?: assigns.op?)
      )
      |> assign(:link_class, PostView.file_link_class(assigns.file))
      |> assign(:deleted_file?, PostView.deleted_file?(assigns.file))
      |> assign(
        :image_classes,
        [
          "post-image",
          if(Map.get(assigns.file, :spoiler, false), do: "spoiler-image", else: nil),
          if(PostView.deleted_file?(assigns.file), do: "deleted", else: nil)
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" ")
      )
      |> assign(:video_file?, PostView.video_file?(assigns.file))

    ~H"""
    <img
      :if={@deleted_file?}
      class={@image_classes}
      src={PostView.file_thumb_src(@file, @config)}
      loading="lazy"
      decoding="async"
      alt=""
    />
    <a
      :if={!@deleted_file?}
      href={@file.file_path}
      target="_blank"
      rel="noopener noreferrer"
      class={@link_class}
      data-video-file={if @video_file?, do: "true", else: nil}
      data-video-url={if @video_file?, do: @file.file_path, else: nil}
      data-default-loop={if @video_file?, do: "loop", else: nil}
    >
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

  def file_image_html(assigns) do
    assigns
    |> with_component_assigns()
    |> file_image()
    |> to_iodata()
    |> IO.iodata_to_binary()
  end

  attr :post, :map, required: true
  attr :board, :map, default: nil
  attr :moderator, :map, default: nil
  attr :secure_manage_token, :string, default: nil

  def post_controls(assigns) do
    controls =
      PostView.post_controls(
        assigns.post,
        assigns.board,
        assigns.moderator,
        assigns.secure_manage_token
      )

    assigns =
      assigns
      |> assign(:controls, controls)
      |> assign(:controls_html, joined_controls_html(controls))

    ~H"""
    <span
      :if={@controls != []}
      class={if is_nil(@post.thread_id), do: "controls op", else: "controls"}
    ><%= raw(@controls_html) %></span>
    """
  end

  attr :post, :map, required: true
  attr :file, :map, required: true
  attr :board, :map, default: nil
  attr :moderator, :map, default: nil
  attr :secure_manage_token, :string, default: nil

  def file_controls(assigns) do
    controls =
      PostView.file_controls(
        assigns.post,
        assigns.file,
        assigns.board,
        assigns.moderator,
        assigns.secure_manage_token
      )

    assigns =
      assigns
      |> assign(:controls, controls)
      |> assign(:controls_html, joined_controls_html(controls))

    ~H"""
    <span :if={@controls != []} class="controls"><%= raw(@controls_html) %></span>
    """
  end

  def file_controls_html(assigns) do
    assigns
    |> with_component_assigns()
    |> file_controls()
    |> to_iodata()
    |> IO.iodata_to_binary()
  end

  attr :control, :map, required: true

  def control_link(assigns) do
    ~H"""
    <a title={@control.title} href={@control.href} onclick={control_onclick(@control)}><%= @control.label %></a>
    """
  end

  def control_link_html(assigns) do
    assigns
    |> with_component_assigns()
    |> control_link()
    |> to_iodata()
    |> IO.iodata_to_binary()
  end

  def post_controls_html(assigns) do
    assigns
    |> with_component_assigns()
    |> post_controls()
    |> to_iodata()
    |> IO.iodata_to_binary()
  end

  defp joined_controls_html(controls) do
    controls
    |> Enum.map(&control_link_html(%{control: &1}))
    |> Enum.join("&nbsp;")
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
        | <a href={"/#{@board_uri}/catalog.html"}><%= @catalog_label %></a>
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
    formatted_html =
      formatted_body_segments_html(%{
        post: assigns.post,
        board: assigns.board,
        thread: assigns.thread,
        config: assigns.config,
        own_post_ids: assigns.own_post_ids,
        show_yous: assigns.show_yous
      })

    assigns =
      assigns
      |> assign(:formatted_html, formatted_html)
      |> assign(:body_attrs, body_attrs(assigns.post, assigns.config, assigns.op?))
      |> assign(
        :body_html,
        div_html(
          body_attrs(assigns.post, assigns.config, assigns.op?),
          body_inner_html(
            assigns.post,
            assigns.config,
            assigns.hide_fileboard,
            assigns.formatted_html
          )
        )
      )

    ~H"""
    <%= raw(@body_html) %>
    """
  end

  attr :post, :map, required: true
  attr :board, :map, required: true
  attr :thread, :map, required: true
  attr :config, :map, required: true
  attr :class, :string, default: nil
  attr :own_post_ids, :any, default: MapSet.new()
  attr :show_yous, :boolean, default: false

  def summary_body(assigns) do
    formatted_html =
      formatted_body_segments_html(%{
        post: assigns.post,
        board: assigns.board,
        thread: assigns.thread,
        config: assigns.config,
        own_post_ids: assigns.own_post_ids,
        show_yous: assigns.show_yous
      })

    assigns =
      assigns
      |> assign(:formatted_html, formatted_html)
      |> assign(:body_html, div_html([class: assigns.class], formatted_html))

    ~H"""
    <%= raw(@body_html) %>
    """
  end

  attr :post, :map, required: true
  attr :board, :map, required: true
  attr :thread, :map, required: true
  attr :config, :map, required: true
  attr :own_post_ids, :any, default: MapSet.new()
  attr :show_yous, :boolean, default: false

  def formatted_body_segments(assigns) do
    assigns =
      assign(
        assigns,
        :formatted_html,
        formatted_body_segments_html(%{
          post: assigns.post,
          board: assigns.board,
          thread: assigns.thread,
          config: assigns.config,
          own_post_ids: assigns.own_post_ids,
          show_yous: assigns.show_yous
        })
      )

    ~H"""
    <%= raw(@formatted_html) %>
    """
  end

  def formatted_body_segments_html(assigns) do
    assigns.post
    |> PostView.body_segments(
      assigns.board,
      assigns.thread,
      assigns.config,
      own_post_ids: Map.get(assigns, :own_post_ids, MapSet.new()),
      show_yous: Map.get(assigns, :show_yous, false)
    )
    |> Enum.with_index()
    |> Enum.map_join(fn
      {segment, 0} -> segment
      {segment, _index} -> "<br/>" <> segment
    end)
  end

  def body_container_html(assigns),
    do:
      div_html(
        body_attrs(assigns.post, assigns.config, Map.get(assigns, :op?, false)),
        body_inner_html(
          assigns.post,
          assigns.config,
          Map.get(assigns, :hide_fileboard, false),
          formatted_body_segments_html(assigns)
        )
      )

  defp body_attrs(post, config, op?) do
    case body_style_attr(post, config, op?) do
      nil -> [class: "body"]
      style -> [class: "body", style: style]
    end
  end

  defp body_inner_html(post, config, hide_fileboard, formatted_html) do
    [
      formatted_html,
      tag_line_html(post, config),
      fileboard_line_html(post, config, hide_fileboard)
    ]
    |> IO.iodata_to_binary()
  end

  defp tag_line_html(%{tag: nil}, _config), do: ""

  defp tag_line_html(post, config) do
    tag_name =
      if is_map(config.allowed_tags) do
        Map.get(config.allowed_tags, post.tag, post.tag)
      else
        post.tag
      end

    span_html([class: "tag-line"], "Tag: #{tag_name}")
  end

  defp fileboard_line_html(post, config, hide_fileboard) do
    if config.fileboard && PostView.show_fileboard_summary?(post) do
      attrs =
        if hide_fileboard do
          [class: "tag-line", style: "display:none"]
        else
          [class: "tag-line"]
        end

      span_html(attrs, "Fileboard: #{PostView.fileboard_summary(post)}")
    else
      ""
    end
  end

  defp div_html(attrs, inner_html) do
    "<div#{attrs_html(attrs)}>#{inner_html}</div>"
  end

  defp span_html(attrs, inner_text) do
    escaped = inner_text |> Plug.HTML.html_escape_to_iodata() |> IO.iodata_to_binary()
    "<span#{attrs_html(attrs)}>#{escaped}</span>"
  end

  defp attrs_html(attrs) do
    attrs
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == false end)
    |> Enum.map_join(fn {key, value} ->
      escaped = value |> to_string() |> Plug.HTML.html_escape_to_iodata() |> IO.iodata_to_binary()
      " #{key}=\"#{escaped}\""
    end)
  end

  def summary_body_html(assigns),
    do:
      div_html(
        [class: assigns.class],
        formatted_body_segments_html(assigns)
      )

  attr :post, :map, required: true
  attr :board, :map, required: true
  attr :thread, :map, required: true
  attr :config, :map, required: true

  def reply_preview(assigns) do
    assigns =
      assign(
        assigns,
        :formatted_html,
        formatted_body_segments_html(%{
          post: assigns.post,
          board: assigns.board,
          thread: assigns.thread,
          config: assigns.config
        })
      )

    ~H"""
    <div class="reply-preview" id={"p#{@post.id}"}>
      <%= if PostView.media_entries(@post, @config) != [] do %>
        <.files_block post={@post} config={@config} />
      <% end %>
      <.post_identity post={@post} board={@board} config={@config} />
      <p><%= raw(@formatted_html) %></p>
    </div>
    """
  end

  def reply_preview_html(assigns) do
    assigns
    |> with_component_assigns()
    |> reply_preview()
    |> to_iodata()
    |> IO.iodata_to_binary()
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
      <%= raw(
        EirinchanWeb.PostView.body_container_html(@post, @board, @thread, @config,
          own_post_ids: @own_post_ids,
          show_yous: @show_yous
        )
      ) %>
    </div>
    <br class="clear" />
    """
  end

  def reply_html(assigns), do: assigns |> reply() |> to_iodata() |> IO.iodata_to_binary()

  def board_pages_html(assigns) do
    assigns
    |> with_component_assigns()
    |> board_pages()
    |> to_iodata()
    |> IO.iodata_to_binary()
  end

  def catalog_pages_html(assigns) do
    assigns
    |> with_component_assigns()
    |> catalog_pages()
    |> to_iodata()
    |> IO.iodata_to_binary()
  end

  defp previous_page(page_data) do
    if page_data.page > 1, do: Enum.at(page_data.pages, page_data.page - 2), else: nil
  end

  defp next_page(page_data) do
    if page_data.page < page_data.total_pages,
      do: Enum.at(page_data.pages, page_data.page),
      else: nil
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

  defp with_component_assigns(assigns) when is_map(assigns) do
    assigns
    |> Map.put_new(:__changed__, %{})
    |> Map.put_new(:__given__, assigns)
  end
end
