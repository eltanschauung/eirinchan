defmodule EirinchanWeb.PostComponents do
  use Phoenix.Component
  import Phoenix.HTML, only: [raw: 1]
  import Phoenix.HTML.Safe, only: [to_iodata: 1]

  alias Eirinchan.Posts.PublicIds
  alias Eirinchan.Settings
  alias EirinchanWeb.{BannerAsset, IpPresentation, PostView}

  attr :groups, :list, required: true
  attr :class_name, :string, default: "boardlist"
  attr :watcher_count, :integer, default: 0
  attr :watcher_unread_count, :integer, default: 0
  attr :watcher_you_count, :integer, default: 0
  attr :mobile_client?, :boolean, default: false
  attr :hide_admin_options, :boolean, default: false

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
      <span :if={!@hide_admin_options} id="admin_options_links" style="float: right;">
        <button
          :if={!@mobile_client?}
          type="button"
          id="watcher-link"
          title={"Watcher#{if @watcher_count > 0, do: " (#{@watcher_count})", else: ""}"}
          aria-label={"Watcher#{if @watcher_count > 0, do: " (#{@watcher_count})", else: ""}"}
          data-count={@watcher_count}
          data-unread-count={@watcher_unread_count}
          class={[
            "js-link-button",
            @watcher_unread_count > 0 && "has-unread",
            @watcher_you_count > 0 && "replies-quoting-you"
          ]}
        >
          👁
        </button>
        <span :if={!@mobile_client?}>&nbsp;</span><a id="admin-link" href="/manage" title="Admin">[Admin]</a><span>&nbsp;</span><a
          id="options-link"
          href="#"
          title="Options"
        >[Options]</a>
      </span>
    </div>
    """
  end

  attr :theme_options, :list, default: []
  attr :theme_label, :string, default: "Yotsuba"

  attr :entries, :map, default: %{}

  def meta_tags(assigns) do
    ~H"""
    <meta :for={{name, content} <- @entries} name={name} content={content} />
    """
  end

  attr :entries, :list, default: []

  def extra_meta_tags(assigns) do
    ~H"""
    <meta
      :for={entry <- @entries}
      name={Map.get(entry, :name)}
      property={Map.get(entry, :property)}
      content={Map.get(entry, :content)}
      value={Map.get(entry, :value)}
    />
    """
  end

  def styles_block(assigns) do
    ~H"""
    <div class="styles">
      <%= for option <- List.wrap(@theme_options) do %>
        <% label = option.label || option.name || "Style" %>
        <a
          href="#"
          class={if label == @theme_label, do: "selected", else: nil}
          data-style-name={label}
        >
          [<%= label %>]
        </a>
      <% end %>
    </div>
    """
  end

  attr :entries, :list, default: nil

  def site_footer(assigns) do
    entries =
      case assigns[:entries] do
        nil -> configured_footer_entries()
        value -> normalize_footer_entries(value)
      end

    assigns = assign(assigns, :entries, entries)

    ~H"""
    <footer>
      <p class="unimportant" style="margin-top:20px;text-align:center;">
        - Tinyboard + vichan 5.2.2 + <a href="https://github.com/username/eirinchan-v1">Eirinchan</a> -<br />
        Tinyboard Copyright &copy; 2010-2014 Tinyboard Development Group<br />
        vichan Copyright &copy; 2012-2026 vichan-devel<br />
      </p>
      <p :for={entry <- @entries} class="unimportant" style="text-align:center;"><%= entry %></p>
    </footer>
    """
  end

  defp configured_footer_entries do
    Settings.current_instance_config()
    |> Map.get(:footer, default_footer_entries())
    |> normalize_footer_entries()
  end

  defp normalize_footer_entries(entries) do
    case entries do
      entries when is_list(entries) ->
        entries
        |> Enum.map(&to_string/1)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      entry when is_binary(entry) ->
        [String.trim(entry)]
        |> Enum.reject(&(&1 == ""))

      _ ->
        default_footer_entries()
    end
  end

  defp default_footer_entries do
    [
      "All trademarks, copyrights, comments, and images on this page are owned by and are the responsibility of their respective parties."
    ]
  end

  def options_shell(assigns) do
    ~H"""
    <div id="options_handler" style="display:none">
      <div id="options_background"></div>
      <div id="options_div">
        <button type="button" id="options_close" class="js-link-button"><i class="fa fa-times"></i></button>
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
              <select data-style-select>
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
          <h2>
            Watcher | <a id="watcher-unwatch-all" href="#" style="color: inherit;">Unwatch All</a>
          </h2>
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

  attr :input_name, :string, required: true
  attr :input_id, :string, default: nil
  attr :multiple, :boolean, default: false
  attr :upload_by_url_enabled, :boolean, default: false

  def file_selector_shell(assigns) do
    ~H"""
    <input
      type="file"
      name={@input_name}
      id={@input_id}
      data-upload-file
      multiple={@multiple}
      hidden
    />
    <noscript>
      <input type="file" name={@input_name} multiple={@multiple} />
    </noscript>
    <div class="dropzone-wrap" data-file-selector-shell>
      <div class="dropzone" tabindex="0">
        <div class="file-hint">Select/drop/paste files here</div>
        <div class="file-thumbs"></div>
      </div>
    </div>
    <div
      :if={@upload_by_url_enabled}
      style="float:none;text-align:left;display:none"
      id="upload_url"
    >
      <label for="file_url">Or URL</label>:
      <input style="display:inline" type="text" id="file_url" name="file_url" size="35" />
    </div>
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
    &nbsp;<a class="post_no" id={"post_no_#{@post_id}"} data-highlight-reply={@post_id} href={@post_href}>No.</a><a
      class="post_no"
      data-cite-reply={@post_id}
      data-cite-mode={quote_mode_value(@quote_mode)}
      href={@quote_href}
      data-quote-to={@quote_to}
      data-quick-reply-thread={@quick_reply_thread}
      {@attrs}
    ><%= @post_id %></a>
    """
  end

  def reply_post_button(assigns) do
    ~H"""
    <a href="#" class="post-btn" title="Post menu">▶</a>
    """
  end

  attr :show, :boolean, default: true
  attr :random_banner, :string, default: "/b.php"
  attr :class_name, :string, default: "board_image"
  attr :style, :string, default: "width:300px;height:100px;cursor:pointer"
  attr :alt, :string, default: ""

  def board_banner(assigns) do
    ~H"""
    <img
      :if={@show}
      class={@class_name}
      data-random-banner={@random_banner}
      src={BannerAsset.banner_url(Settings.current_instance_config())}
      style={@style}
      alt={@alt}
    />
    """
  end

  attr :post, :map, required: true
  attr :backlinks_map, :map, default: %{}
  attr :board, :map, default: nil
  attr :thread, :map, default: nil
  attr :config, :map, default: nil

  def backlinks(assigns) do
    backlinks =
      assigns.post
      |> PublicIds.public_id()
      |> then(&Map.get(assigns.backlinks_map || %{}, &1, []))

    assigns =
      assigns
      |> assign(:backlinks, backlinks)
      |> assign(:backlink_base_href, backlink_base_href(assigns))

    ~H"""
    <span :if={@backlinks != []} class="mentioned">
      <%= for backlink_id <- @backlinks do %>
        <a
          class={"mentioned-#{backlink_id}"}
          data-highlight-reply={backlink_id}
          href={@backlink_base_href <> "##{backlink_id}"}
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

  defp backlink_base_href(%{board: board, thread: thread, config: config})
       when not is_nil(board) and not is_nil(thread) and not is_nil(config) do
    PostView.thread_path(board, thread, config)
  end

  defp backlink_base_href(_assigns), do: ""

  attr :thread_id, :integer, required: true
  attr :watch, :map, default: %{watched: false, unread_count: 0}
  attr :show_hide, :boolean, default: false

  def thread_top_controls(assigns) do
    watched = Map.get(assigns.watch || %{}, :watched, false)
    assigns = assign(assigns, :watched, watched)

    ~H"""
    <span class="thread-top-controls">
      <button :if={@show_hide} type="button" class="hide-thread-link js-link-button" title="Hide thread">
        [–]
      </button>
      <a href="#" class="post-btn" title="Post menu">▶</a>
      <button
        type="button"
        class={["watch-thread-link", "js-link-button", @watched && "watched"]}
        title={if @watched, do: "Unwatch Thread", else: "Watch Thread"}
        data-thread-watch
        data-thread-id={@thread_id}
        data-watched={to_string(@watched)}
      >
      </button>
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
        data-submit-form="admin-shortcuts-logout-form"
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
    assigns = assign(assigns, :media_entries, PostView.media_entries(assigns.post, assigns.config))

    ~H"""
    <div class="files">
      <%= for media <- @media_entries do %>
        <.embed_media :if={PostView.embed_entry?(media)} html={media.embed_html} />
        <.file_block
          :if={!PostView.embed_entry?(media)}
          post={@post}
          file={media}
          config={@config}
          op?={@op?}
          board={@board}
          moderator={@moderator}
          secure_manage_token={@secure_manage_token}
        />
      <% end %>
    </div>
    """
  end

  attr :html, :string, default: nil

  def embed_media(assigns) do
    ~H"""
    <%= raw(@html || "") %>
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
        <a href={@file.file_path} class="postfilename" title={PostView.original_file_name(@file)}>
          <%= PostView.display_file_name(@file, @config) %>
        </a>
        <a
          href={@file.file_path}
          download={PostView.original_file_name(@file) || PostView.stored_file_name(@file)}
          class="fa fa-download download-button"
          title="Download"
          aria-label="Download"
        ></a>
        <span>(<%= PostView.file_inline_details_text(@file) %>)</span>
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
          if(PostView.deleted_file?(assigns.file), do: "file_deleted", else: nil),
          if(Map.get(assigns.file, :spoiler, false), do: "spoiler-image", else: nil),
          if(PostView.deleted_file?(assigns.file), do: "deleted", else: nil)
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" ")
      )
      |> assign(:video_file?, PostView.video_file?(assigns.file))
      |> assign(:expandable_image?, PostView.file_link_class(assigns.file) != "file")

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
      data-inline-expandable={if @expandable_image?, do: "true", else: nil}
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
      <img
        :if={@expandable_image?}
        class="full-image"
        data-full-image-src={@file.file_path}
        style="display:none"
        alt="Fullsized image"
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

    ~H"""
    <span
      :if={@controls != []}
      class={if is_nil(@post.thread_id), do: "controls op", else: "controls"}
    ><%= for {control, index} <- Enum.with_index(@controls) do %><%= if index > 0, do: raw("&nbsp;") %><.control_link control={control} /><% end %></span>
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

    ~H"""
    <span :if={@controls != []} class="controls"><%= for {control, index} <- Enum.with_index(@controls) do %><%= if index > 0, do: raw("&nbsp;") %><.control_link control={control} /><% end %></span>
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
    <a
      title={@control.title}
      href={@control.href}
      data-confirm-message={confirm_message(@control)}
      data-secure-href={secure_href(@control)}
    ><%= @control.label %></a>
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
      |> assign(:tag_line_text, tag_line_text(assigns.post, assigns.config))
      |> assign(:fileboard_line_text, fileboard_line(assigns.post, assigns.config, assigns.hide_fileboard))

    ~H"""
    <div {@body_attrs}><%= raw(@formatted_html) %><span :if={@tag_line_text} class="tag-line"><%= @tag_line_text %></span><span
        :if={@fileboard_line_text}
        class="tag-line"
        style={if @hide_fileboard, do: "display:none", else: nil}
      ><%= @fileboard_line_text %></span></div>
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

    ~H"""
    <div class={@class}><%= raw(@formatted_html) %></div>
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
    body_html =
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

    body_html <>
      (PostView.public_ban_message_html(assigns.post) || "") <>
      (PostView.public_gap_warning_html(assigns.post, assigns.config) || "")
  end

  # Compatibility wrapper for builder/test paths that still consume binary HTML.
  def body_container_html(assigns) do
    assigns
    |> with_component_assigns()
    |> body_container()
    |> to_iodata()
    |> IO.iodata_to_binary()
  end

  defp body_attrs(post, config, op?) do
    case body_style_attr(post, config, op?) do
      nil -> [class: "body"]
      style -> [class: "body", style: style]
    end
  end

  defp tag_line_text(%{tag: nil}, _config), do: nil

  defp tag_line_text(post, config) do
    tag_name =
      if is_map(config.allowed_tags) do
        Map.get(config.allowed_tags, post.tag, post.tag)
      else
        post.tag
      end

    "Tag: #{tag_name}"
  end

  defp fileboard_line(post, config, _hide_fileboard) do
    if config.fileboard && PostView.show_fileboard_summary?(post) do
      "Fileboard: #{PostView.fileboard_summary(post)}"
    else
      nil
    end
  end

  # Compatibility wrapper for builder/test paths that still consume binary HTML.
  def summary_body_html(assigns),
    do:
      assigns
      |> with_component_assigns()
      |> summary_body()
      |> to_iodata()
      |> IO.iodata_to_binary()

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
      |> assign(:public_post_id, PublicIds.public_id(assigns.post))

    ~H"""
    <div class="reply-preview" id={"p#{@public_post_id}"}>
      <%= if PostView.media_entries(@post, @config) != [] do %>
        <.files_block post={@post} config={@config} />
      <% end %>
      <.post_identity post={@post} board={@board} config={@config} />
      <p><.formatted_body_segments post={@post} board={@board} thread={@thread} config={@config} /></p>
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
    public_post_id = PublicIds.public_id(assigns.post)
    assigns = assign(assigns, :public_post_id, public_post_id)

    ~H"""
    <div class="post reply" id={"reply_#{@public_post_id}"}>
      <p class="intro">
        <a id={to_string(@public_post_id)} class="post_anchor"></a>
        <input
          :if={!@mobile_client?}
          type="checkbox"
          class="delete"
          name={"delete_#{@public_post_id}"}
          id={"delete_#{@public_post_id}"}
          value={@public_post_id}
          data-post-select=""
        />
        <.reply_post_button post_target={"reply_#{@public_post_id}"} />
        <label for={"delete_#{@public_post_id}"}>
          <.post_identity
            post={@post}
            config={@config}
            board={@board}
            moderator={@moderator}
            own={@show_yous and MapSet.member?(@own_post_ids, @public_post_id)}
          />
        </label>
        <.post_number_links
          post_id={@public_post_id}
          post_href={PostView.thread_path(@board, @thread, @config) <> "##{@public_post_id}"}
          quote_href={PostView.reply_path(@board, @thread, @post, @config, :quote)}
          quote_to={@public_post_id}
        />
        <.backlinks
          post={@post}
          backlinks_map={@backlinks_map}
          board={@board}
          thread={@thread}
          config={@config}
        />
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

  def reply_html(assigns) do
    assigns
    |> with_component_assigns()
    |> reply()
    |> to_iodata()
    |> IO.iodata_to_binary()
  end

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

  defp quote_mode_value(:navigate), do: "navigate"
  defp quote_mode_value(_mode), do: "inline"

  defp visible_ip(post, board, moderator) do
    if PostView.can_view_ip?(moderator, board) and post.ip_subnet do
      IpPresentation.display_ip(post.ip_subnet, moderator)
    end
  end

  defp body_style_attr(post, config, _op?) do
    if length(PostView.media_entries(post, config)) > 1, do: "clear:both", else: nil
  end

  defp confirm_message(%{kind: :confirm, confirm: message}), do: message
  defp confirm_message(_control), do: nil

  defp secure_href(%{kind: :confirm, secure: href}), do: href
  defp secure_href(_control), do: nil

  defp with_component_assigns(assigns) when is_map(assigns) do
    assigns
    |> Map.put_new(:__changed__, %{})
    |> Map.put_new(:__given__, assigns)
  end
end
