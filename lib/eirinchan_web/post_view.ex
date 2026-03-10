defmodule EirinchanWeb.PostView do
  @moduledoc false

  import Phoenix.HTML, only: [html_escape: 1, safe_to_string: 1]

  alias Eirinchan.Boardlist
  alias Eirinchan.Moderation
  alias Eirinchan.Posts.PostFile
  alias Eirinchan.Themes
  alias Eirinchan.ThreadPaths
  alias Eirinchan.WhaleStickers
  alias EirinchanWeb.{IpPresentation, ManageSecurity}

  def template_assigns(board, post, config) do
    %{
      board: board,
      board_title: board.title,
      post: post,
      config: config
    }
  end

  def post_title(_board, post, config) do
    cond do
      present?(post.subject) ->
        post.subject

      config.fileboard && present?(post.file_name) ->
        post.file_name

      is_nil(post.thread_id) ->
        "Thread ##{post.id}"

      true ->
        "Reply ##{post.id}"
    end
  end

  def show_body?(post, config) do
    present?(post.body) or not config.fileboard
  end

  def fileboard_summary(post) do
    count = media_count(post)
    noun = if count == 1, do: "file", else: "files"
    "#{count} #{noun}"
  end

  def show_fileboard_summary?(post), do: media_count(post) > 0

  def feedback_actions do
    [
      %{key: "mark_read", label: "Mark as Read", method: "PATCH"},
      %{key: "add_note", label: "Add Note", method: "POST"},
      %{key: "delete", label: "Delete", method: "DELETE"}
    ]
  end

  def display_name(post, config) do
    case normalize_string(post.name) do
      nil -> config.anonymous
      value -> value
    end
  end

  def name_html(post, config) do
    name_html(display_name(post, config), Map.get(post, :email), config)
  end

  def name_html(name, email, config) do
    inner = ~s(<span class="name">#{html_escape_to_string(name)}</span>)

    if email_link?(email, config) do
      ~s(<a class="email" href="mailto:#{html_escape_to_string(email)}">#{inner}</a>)
    else
      inner
    end
  end

  def board_heading(board), do: "/#{board.uri}/ - #{board.title}"

  def thread_path(board, post, config), do: ThreadPaths.thread_path(board, post, config)

  def reply_path(board, thread, post, config, mode \\ :post) do
    suffix =
      case mode do
        :quote -> "#q#{post.id}"
        _ -> "#p#{post.id}"
      end

    thread_path(board, thread, config) <> suffix
  end

  def post_number_links_html(post_id, post_href, quote_href, attrs \\ []) do
    quote_attrs =
      attrs
      |> Enum.map(fn {key, value} ->
        ~s( #{key}="#{html_escape_to_string(value)}")
      end)
      |> Enum.join("")

    ~s|&nbsp;<a class="post_no" id="post_no_#{post_id}" onclick="highlightReply(#{post_id})" href="#{html_escape_to_string(post_href)}">No.</a><a class="post_no" onclick="citeReply(#{post_id})" href="#{html_escape_to_string(quote_href)}"#{quote_attrs}>#{post_id}</a>|
  end

  def boardlist_groups(boards) do
    Boardlist.configured_groups(boards)
  end

  def default_boardlist_groups(boards) do
    [
      Enum.map(boards, fn board ->
        %{
          href: "/#{board.uri}/index.html",
          label: board.uri,
          title: board.title
        }
      end),
      [%{href: "/", label: "Home", title: "Home"}]
    ]
    |> Enum.reject(&(&1 == []))
  end

  def boardlist_html(groups, class_name \\ "boardlist") do
    spans =
      Enum.map_join(groups, "  ", fn group ->
        links = group[:links] || group

        description_attr =
          if group[:description], do: ~s( data-description="#{group[:description]}"), else: ""

        links_html =
          Enum.map_join(links, " / ", fn link ->
            ~s(<a href="#{html_escape_to_string(link.href)}" title="#{html_escape_to_string(link.title)}">#{html_escape_to_string(link.label)}</a>)
          end)

        ~s(<span class="sub"#{description_attr}>[ #{links_html} ]</span>)
      end)

    ~s(<div class="#{class_name}">#{spans}</div>)
  end

  def pages_html(page_data, board_uri, config) do
    previous_html =
      if page_data.page > 1 do
        previous = Enum.at(page_data.pages, page_data.page - 2)
        ~s(<a href="#{html_escape_to_string(previous.link)}">Previous</a>)
      else
        "Previous"
      end

    page_links =
      Enum.map_join(page_data.pages, " ", fn page ->
        if page.num == page_data.page do
          ~s([<a class="selected">#{page.num}</a>])
        else
          ~s([<a href="#{html_escape_to_string(page.link)}">#{page.num}</a>])
        end
      end)

    next_html =
      if page_data.page < page_data.total_pages do
        next = Enum.at(page_data.pages, page_data.page)

        ~s(<form action="#{html_escape_to_string(next.link)}" method="get"><input type="submit" value="Next" /></form>)
      else
        ""
      end

    catalog_label =
      config
      |> Map.get(:catalog_name, "Catalog")
      |> to_string()
      |> String.trim()
      |> case do
        "" -> "Catalog"
        value -> value
      end

    catalog_link =
      if Themes.page_theme_enabled?("catalog"),
        do: ~s( | <a href="/#{board_uri}/catalog.html">#{html_escape_to_string(catalog_label)}</a>),
        else: ""

    ~s(<div class="pages">#{previous_html}  #{page_links}#{if next_html != "", do: "  " <> next_html, else: ""}#{catalog_link}</div>)
  end

  def catalog_pages_html(page_data) do
    page_links =
      Enum.map_join(page_data.pages, " ", fn page ->
        if page.num == page_data.page do
          ~s([<a class="selected">#{page.num}</a>])
        else
          ~s([<a href="#{html_escape_to_string(page.link)}">#{page.num}</a>])
        end
      end)

    ~s(<div class="pages">#{page_links}</div>)
  end

  def post_flags(post, config) do
    if Map.get(config, :display_flags, true) do
      do_post_flags(post, config)
    else
      []
    end
  end

  def flag_style(config) do
    case Map.get(config, :flag_style) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp do_post_flags(post, config) do
    Enum.zip(post.flag_codes || [], post.flag_alts || [])
    |> Enum.map(fn {code, alt} ->
      %{
        code: code,
        alt: alt,
        src: flag_path(code, config)
      }
    end)
  end

  def state_icons(post, config) do
    []
    |> maybe_add_icon(post.sticky, config.image_sticky, "Important")
    |> maybe_add_icon(post.locked, config.image_locked, "Locked")
    |> maybe_add_icon(post.sage, config.image_bumplocked, "Bumplocked")
    |> maybe_add_icon(post.cycle, config.image_cyclical, "Cyclical")
  end

  def formatted_timestamp(%{inserted_at: %NaiveDateTime{} = inserted_at}) do
    Calendar.strftime(inserted_at, "%m/%d/%y (%a) %H:%M:%S")
  end

  def formatted_timestamp(%{inserted_at: %DateTime{} = inserted_at}) do
    Calendar.strftime(DateTime.to_naive(inserted_at), "%m/%d/%y (%a) %H:%M:%S")
  end

  def formatted_timestamp(_post), do: ""

  def iso_timestamp(%{inserted_at: %DateTime{} = inserted_at}),
    do: DateTime.to_iso8601(inserted_at)

  def iso_timestamp(%{inserted_at: %NaiveDateTime{} = inserted_at}),
    do: NaiveDateTime.to_iso8601(inserted_at)

  def iso_timestamp(_post), do: nil

  def unix_timestamp(%DateTime{} = value), do: DateTime.to_unix(value)

  def unix_timestamp(%NaiveDateTime{} = value),
    do: value |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()

  def unix_timestamp(_value), do: 0

  def ip_link_html(post, board, moderator) do
    if can_view_ip?(moderator, board) and present?(post.ip_subnet) do
      ip = IpPresentation.display_ip(post.ip_subnet, moderator)

      ~s( [<a class="ip-link" style="margin:0;" href="/mod.php?/IP/#{html_escape_to_string(ip)}">#{html_escape_to_string(ip)}</a>])
    else
      nil
    end
  end

  def can_view_ip?(moderator, board \\ nil)

  def can_view_ip?(nil, _board), do: false

  def can_view_ip?(moderator, nil) do
    role_level(moderator.role) >= permission_level(:show_ip_global)
  end

  def can_view_ip?(moderator, board) do
    can_moderate?(moderator, board, :show_ip)
  end

  def post_controls_html(post, board, moderator, session_token) do
    if can_render_controls?(moderator, board) do
      links =
        []
        |> maybe_add_control(
          can_moderate?(moderator, board, :delete),
          confirm_control(post, board, session_token, :delete)
        )
        |> maybe_add_control(
          can_moderate?(moderator, board, :deletebyip),
          confirm_control(post, board, session_token, :deletebyip)
        )
        |> maybe_add_control(
          can_moderate?(moderator, board, :deletebyip_global),
          confirm_control(post, board, session_token, :deletebyip_global)
        )
        |> maybe_add_control(
          can_moderate?(moderator, board, :ban),
          plain_control(post, board, :ban)
        )
        |> maybe_add_control(
          can_moderate?(moderator, board, :bandelete),
          plain_control(post, board, :bandelete)
        )
        |> maybe_add_control(
          thread_op?(post) and can_moderate?(moderator, board, :sticky),
          toggle_control(post, board, session_token, :sticky)
        )
        |> maybe_add_control(
          thread_op?(post) and can_moderate?(moderator, board, :bumplock),
          toggle_control(post, board, session_token, :bumplock)
        )
        |> maybe_add_control(
          thread_op?(post) and can_moderate?(moderator, board, :lock),
          toggle_control(post, board, session_token, :lock)
        )
        |> maybe_add_control(
          can_moderate?(moderator, board, :move),
          plain_control(post, board, :move)
        )
        |> maybe_add_control(
          thread_op?(post) and can_moderate?(moderator, board, :cycle),
          toggle_control(post, board, session_token, :cycle)
        )
        |> maybe_add_control(
          can_moderate?(moderator, board, :editpost),
          plain_control(post, board, :editpost)
        )

      case links do
        [] ->
          nil

        entries ->
          class_name = if thread_op?(post), do: "controls op", else: "controls"
          ~s(<span class="#{class_name}">#{Enum.join(entries, "&nbsp;")}</span>)
      end
    else
      nil
    end
  end

  def reply_html(post, board, thread, config, moderator \\ nil, session_token \\ nil) do
    identity =
      [
        if(present?(post.subject),
          do: ~s(<span class="subject">#{html_escape_to_string(post.subject)}</span>),
          else: nil
        ),
        name_html(post, config),
        if(present?(post.tripcode),
          do: ~s(<span class="trip">#{html_escape_to_string(post.tripcode)}</span>),
          else: nil
        ),
        ip_link_html(post, board, moderator),
        post_flags_html(post, config),
        time_html(post)
      ]
      |> Enum.reject(&blank_fragment?/1)
      |> Enum.join(" ")

    intro =
      [
        ~s(<a id="#{post.id}" class="post_anchor"></a>),
        ~s(<input type="checkbox" class="delete" name="delete_#{post.id}" id="delete_#{post.id}" value="#{post.id}" data-post-select />),
        ~s(<label for="delete_#{post.id}">),
        identity,
        "</label>",
        post_number_links_html(
          post.id,
          thread_path(board, thread, config) <> "##{post.id}",
          reply_path(board, thread, post, config, :quote),
          "data-quote-to": post.id
        )
      ]
      |> Enum.join("")

    ~s(<div class="post reply" id="reply_#{post.id}"><p class="intro">#{intro}</p><div class="files">#{files_html(post, config, moderator, board, session_token)}</div>#{post_controls_html(post, board, moderator, session_token) || ""}#{reply_body_container_html(post, board, thread, config)}</div><br class="clear" />)
  end

  def file_size_text(file), do: human_file_size(Map.get(file, :file_size))
  def file_dimensions(file), do: dimensions(file)
  def file_class(post), do: if(media_count(post) > 1, do: "file multifile", else: "file")

  def file_image_html(file, config, opts \\ []) do
    thumb_style_attr =
      case thumb_style(file, config, opts) do
        nil -> ""
        style -> ~s( style="#{html_escape_to_string(style)}")
      end

    class_attr =
      case file_link_class(file) do
        nil -> ""
        value -> ~s( class="#{html_escape_to_string(value)}")
      end

    ~s|<a href="#{html_escape_to_string(file.file_path)}" target="_blank"#{class_attr}><img class="post-image" src="#{html_escape_to_string(file.thumb_path || file.file_path)}"#{thumb_style_attr} alt="" /></a>|
  end

  def post_container_style(post), do: if(media_count(post) > 1, do: "clear:both", else: nil)
  def reply_body_style(reply, config), do: body_style(reply, config)

  def media_entries(post, config) do
    embed_entries =
      if has_embed?(post) do
        [
          %{
            kind: :embed,
            position: 0,
            embed: post.embed,
            embed_html: embed_html(post, config),
            thumb_path: youtube_thumbnail(post.embed)
          }
        ]
      else
        []
      end

    file_entries =
      post
      |> all_files()
      |> Enum.with_index(length(embed_entries))
      |> Enum.map(fn {file, index} ->
        Map.put(file, :kind, :file)
        |> Map.put(:position, index)
      end)

    embed_entries ++ file_entries
  end

  def files_html(post, config, moderator \\ nil, board \\ nil, session_token \\ nil) do
    Enum.map_join(media_entries(post, config), "", fn media ->
      if embed_entry?(media) do
        media.embed_html || ""
      else
        file = media
        class_name = file_class(post)

        style_attr =
          case multifile_style(file, config, multifile: media_multifile?(post)) do
            nil -> ""
            style -> ~s( style="#{html_escape_to_string(style)}")
          end

        dimensions =
          case file_dimensions(file) do
            nil -> ""
            value -> ", " <> value
          end

        controls = file_controls_html(post, file, board, moderator, session_token) || ""

        ~s|<div class="#{class_name}"#{style_attr}><p class="fileinfo">File: <a href="#{html_escape_to_string(file.file_path)}">#{html_escape_to_string(stored_file_name(file))}</a><span>(#{html_escape_to_string(file_size_text(file))}#{dimensions}, <span class="postfilename" title="#{html_escape_to_string(original_file_name(file))}">#{html_escape_to_string(display_file_name(file, config))}</span>)</span>#{controls}</p>#{file_image_html(file, config)}</div>|
      end
    end)
  end

  def file_controls_html(post, file, board, moderator, session_token) do
    if present?(Map.get(file, :file_path)) do
      controls =
        []
        |> maybe_add_control(
          can_moderate?(moderator, board, :deletefile),
          file_confirm_control(post, file, board, session_token, :deletefile)
        )
        |> maybe_add_control(
          not Map.get(file, :spoiler, false) and can_moderate?(moderator, board, :spoilerimage),
          file_confirm_control(post, file, board, session_token, :spoilerimage)
        )

      case controls do
        [] -> nil
        entries -> ~s(<span class="controls">#{Enum.join(entries, "&nbsp;")}</span>)
      end
    end
  end

  defp post_flags_html(post, config) do
    Enum.map_join(post_flags(post, config), "", fn flag ->
      style_attr =
        case flag_style(config) do
          nil -> ""
          value -> ~s( style="#{html_escape_to_string(value)}")
        end

      ~s(<img class="flag" src="#{html_escape_to_string(flag.src)}" alt="#{html_escape_to_string(flag.alt)}" title="#{html_escape_to_string(flag.alt)}"#{style_attr} />)
    end)
  end

  def embed_entry?(%{kind: :embed}), do: true
  def embed_entry?(_entry), do: false

  def media_multifile?(post), do: media_count(post) > 1

  def catalog_label(post, config) do
    cond do
      present?(post.subject) -> post.subject
      config.fileboard && present?(post.file_name) -> post.file_name
      true -> nil
    end
  end

  def all_files(post) do
    primary =
      if present?(post.file_path) do
        [
          %{
            file_name: post.file_name,
            file_path: post.file_path,
            thumb_path: post.thumb_path,
            file_size: post.file_size,
            file_type: post.file_type,
            image_width: post.image_width,
            image_height: post.image_height,
            spoiler: Map.get(post, :spoiler, false)
          }
        ]
      else
        []
      end

    primary ++ extra_files(post)
  end

  def file_display_name(file) do
    file.file_name ||
      case Map.get(file, :file_path) do
        nil -> "upload"
        path -> Path.basename(path)
      end
  end

  def stored_file_name(file) do
    file
    |> Map.get(:file_path)
    |> case do
      nil -> file_display_name(file)
      path -> Path.basename(path)
    end
  end

  def file_link_class(file) do
    if expandable_image?(file), do: nil, else: "file"
  end

  def original_file_name(file) do
    file_display_name(file)
  end

  def display_file_name(file, config) do
    original = original_file_name(file)
    limit = max(Map.get(config, :max_filename_display_length, 30), 1)

    cond do
      original in [nil, ""] ->
        original

      String.length(original) <= limit ->
        original

      true ->
        ext = Path.extname(original)
        base = Path.rootname(original, ext)
        suffix = "…" <> ext
        keep = max(limit - String.length(suffix), 1)
        String.slice(base, 0, keep) <> suffix
    end
  end

  def file_info(file) do
    info =
      [human_file_size(file.file_size), dimensions(file)]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    if info == "" do
      file_display_name(file)
    else
      "#{file_display_name(file)} (#{info})"
    end
  end

  def file_info_details(file, config) do
    parts =
      [human_file_size(file.file_size), dimensions(file), original_file_name_detail(file, config)]
      |> Enum.reject(&is_nil/1)

    Enum.join(parts, ", ")
  end

  def thumb_style(file, config, opts \\ []) do
    op? = Keyword.get(opts, :op?, false)
    max_width = if op?, do: config.thumb_op_width, else: config.thumb_width
    max_height = if op?, do: config.thumb_op_height, else: config.thumb_height

    case fit_dimensions(
           Map.get(file, :image_width),
           Map.get(file, :image_height),
           max_width,
           max_height
         ) do
      {width, height} -> "width:#{width}px;height:#{height}px"
      nil -> nil
    end
  end

  defp expandable_image?(file) do
    ext =
      file
      |> file_display_name()
      |> String.downcase()
      |> Path.extname()

    image_exts = [".jpg", ".jpeg", ".gif", ".png", ".webp"]

    cond do
      ext in [".webm", ".mp4"] -> false
      ext in image_exts -> true
      is_binary(file[:file_type]) -> String.starts_with?(file.file_type, "image/")
      true -> false
    end
  end

  def multifile_style(file, config, opts \\ []) do
    if Keyword.get(opts, :multifile, false) do
      case fit_dimensions(
             Map.get(file, :image_width),
             Map.get(file, :image_height),
             config.thumb_width,
             config.thumb_height
           ) do
        {width, _height} -> "width:#{width + 40}px"
        nil -> nil
      end
    else
      nil
    end
  end

  def body_html(post, board, thread, config) do
    post.body
    |> Kernel.||("")
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> html_escape()
    |> safe_to_string()
    |> String.split("\n", trim: false)
    |> Enum.map(&format_body_line(&1, board, thread, config))
    |> Enum.join("<br/>")
  end

  def time_html(post) do
    ~s(<time datetime="#{html_escape_to_string(iso_timestamp(post))}">#{html_escape_to_string(formatted_timestamp(post))}</time>)
  end

  def body_container_html(post, board, thread, config, opts \\ []) do
    body = body_html(post, board, thread, config)
    style_attr = body_style_attr(post, config, opts)

    tag_html =
      case post.tag do
        nil ->
          ""

        tag ->
          label =
            if is_map(config.allowed_tags), do: Map.get(config.allowed_tags, tag, tag), else: tag

          ~s(<span class="tag-line">Tag: #{html_escape_to_string(label)}</span>)
      end

    fileboard_hidden? = Keyword.get(opts, :hide_fileboard, false)

    fileboard_html =
      if config.fileboard and show_fileboard_summary?(post) do
        hidden_attr = if fileboard_hidden?, do: ~s( style="display:none"), else: ""

        ~s(<span class="tag-line"#{hidden_attr}>Fileboard: #{html_escape_to_string(fileboard_summary(post))}</span>)
      else
        ""
      end

    ~s(<div class="body"#{style_attr}>#{body}#{tag_html}#{fileboard_html}</div>)
  end

  def reply_body_container_html(post, board, thread, config) do
    body = body_html(post, board, thread, config)
    style_attr = body_style_attr(post, config)

    tag_html =
      case post.tag do
        nil ->
          ""

        tag ->
          label =
            if is_map(config.allowed_tags), do: Map.get(config.allowed_tags, tag, tag), else: tag

          ~s(<span class="tag-line">Tag: #{html_escape_to_string(label)}</span>)
      end

    fileboard_html =
      if config.fileboard and show_fileboard_summary?(post) do
        ~s(<span class="tag-line">Fileboard: #{html_escape_to_string(fileboard_summary(post))}</span>)
      else
        ""
      end

    ~s(<div class="body"#{style_attr}>#{body}#{tag_html}#{fileboard_html}</div>)
  end

  def has_embed?(%{embed: embed}) when is_binary(embed), do: String.trim(embed) != ""
  def has_embed?(_post), do: false

  def embed_html(%{embed: embed}, config), do: embed_html(embed, config)

  def embed_html(embed, config) when is_binary(embed) do
    cond do
      embed == "" ->
        nil

      String.starts_with?(embed, "<") ->
        embed

      true ->
        config
        |> Map.get(:embedding, [])
        |> Enum.find_value(fn rule ->
          case normalize_embedding_rule(rule) do
            {:ok, regex, template} ->
              case Regex.run(regex, embed) do
                nil -> nil
                captures -> apply_embedding_template(template, captures, config)
              end

            :error ->
              nil
          end
        end)
        |> Kernel.||("Embedding error.")
    end
  end

  def embed_html(_embed, _config), do: nil

  def catalog_media_path(post, config) do
    cond do
      has_embed?(post) ->
        youtube_thumbnail(post.embed)

      present?(post.thumb_path) ->
        post.thumb_path

      present?(post.file_path) ->
        post.file_path

      true ->
        Map.get(config, :image_deleted)
    end
  end

  def catalog_fullimage_path(post, _config) do
    cond do
      has_embed?(post) ->
        youtube_thumbnail(post.embed)

      present?(post.file_path) ->
        post.file_path

      true ->
        nil
    end
  end

  def omitted_text(summary) do
    parts =
      []
      |> maybe_add_omitted(summary.omitted_posts, "posts")
      |> maybe_add_omitted(summary.omitted_images, "image replies")

    case parts do
      [] -> nil
      values -> Enum.join(values, " and ") <> " omitted. Click reply to view."
    end
  end

  def primary_file?(_post, %PostFile{}), do: false

  def primary_file?(post, file),
    do: present?(post.file_path) and Map.get(file, :file_path) == post.file_path

  defp extra_files(%{extra_files: %Ecto.Association.NotLoaded{}}), do: []

  defp extra_files(%{extra_files: files}) when is_list(files),
    do: Enum.sort_by(files, &Map.get(&1, :position, 0))

  defp extra_files(_post), do: []

  defp can_render_controls?(nil, _board), do: false
  defp can_render_controls?(_moderator, nil), do: false
  defp can_render_controls?(moderator, board), do: Moderation.board_access?(moderator, board)

  defp can_moderate?(nil, _board, _permission), do: false
  defp can_moderate?(_moderator, board, _permission) when is_nil(board), do: false

  defp can_moderate?(moderator, board, permission) do
    Moderation.board_access?(moderator, board) and
      role_level(moderator.role) >= permission_level(permission)
  end

  defp role_level("admin"), do: 30
  defp role_level("mod"), do: 20
  defp role_level("janitor"), do: 10
  defp role_level(_), do: 0

  defp permission_level(:show_ip), do: 20
  defp permission_level(:show_ip_global), do: 30
  defp permission_level(:delete), do: 10
  defp permission_level(:ban), do: 20
  defp permission_level(:bandelete), do: 20
  defp permission_level(:deletebyip), do: 20
  defp permission_level(:deletebyip_global), do: 30
  defp permission_level(:sticky), do: 20
  defp permission_level(:cycle), do: 20
  defp permission_level(:lock), do: 20
  defp permission_level(:bumplock), do: 20
  defp permission_level(:editpost), do: 30
  defp permission_level(:move), do: 20
  defp permission_level(:deletefile), do: 10
  defp permission_level(:spoilerimage), do: 10

  defp body_style(post, config, opts \\ []) do
    cond do
      media_count(post) > 1 ->
        "clear:both"

      ergonomic_body_clear?(post, config, opts) ->
        "clear:left;margin-left:0;padding-right:0.5em;margin-top:0.35em"

      true ->
        nil
    end
  end

  defp body_style_attr(post, config, opts \\ []) do
    case body_style(post, config, opts) do
      nil -> ""
      style -> ~s( style="#{html_escape_to_string(style)}")
    end
  end

  defp ergonomic_body_clear?(post, config, opts) do
    media_count(post) > 0 and
      body_complex_enough?(post) and
      media_display_width(post, config, opts) >= 200
  end

  defp body_complex_enough?(%{body: body}) when is_binary(body) do
    lines =
      body
      |> String.split("\n", trim: false)
      |> length()

    longest_line =
      body
      |> String.split("\n", trim: false)
      |> Enum.map(&String.length/1)
      |> Enum.max(fn -> 0 end)

    lines >= 4 or String.length(body) >= 160 or longest_line >= 48
  end

  defp body_complex_enough?(_post), do: false

  defp media_display_width(post, config, opts) do
    op? = Keyword.get(opts, :op?, thread_op?(post))

    case media_entries(post, config) do
      [%{kind: :embed} | _] ->
        config.embed_width || 0

      [file | _] ->
        case fit_dimensions(
               Map.get(file, :image_width),
               Map.get(file, :image_height),
               if(op?, do: config.thumb_op_width, else: config.thumb_width),
               if(op?, do: config.thumb_op_height, else: config.thumb_height)
             ) do
          {width, _height} -> width
          nil -> 0
        end

      [] ->
        0
    end
  end

  defp email_link?(email, config) when is_binary(email) do
    trimmed = String.trim(email)

    trimmed != "" and
      Map.get(config, :hide_email, false) != true and
      (Map.get(config, :hide_sage, false) != true or trimmed != "sage")
  end

  defp email_link?(_email, _config), do: false

  defp confirm_control(post, board, session_token, action) do
    %{href: href, secure: secure_href, title: title, label: label, confirm: message} =
      control_metadata(post, board, session_token, action)

    ~s|<a onclick="if (event.which==2) return true;if (confirm('#{js_escape(message)}')) document.location='#{html_escape_to_string(secure_href)}';return false;" title="#{html_escape_to_string(title)}" href="#{html_escape_to_string(href)}">#{label}</a>|
  end

  defp plain_control(post, board, action) do
    %{href: href, title: title, label: label} = control_metadata(post, board, nil, action)

    ~s(<a title="#{html_escape_to_string(title)}" href="#{html_escape_to_string(href)}">#{label}</a>)
  end

  defp toggle_control(post, board, session_token, action),
    do: confirm_control(post, board, session_token, action)

  defp control_metadata(post, board, session_token, action) do
    action_path =
      case action do
        :delete -> "#{board.uri}/delete/#{post.id}"
        :deletebyip -> "#{board.uri}/deletebyip/#{post.id}"
        :deletebyip_global -> "#{board.uri}/deletebyip/#{post.id}/global"
        :ban -> "#{board.uri}/ban/#{post.id}"
        :bandelete -> "#{board.uri}/ban&delete/#{post.id}"
        :sticky -> "#{board.uri}/#{if post.sticky, do: "unsticky", else: "sticky"}/#{post.id}"
        :bumplock -> "#{board.uri}/#{if post.sage, do: "bumpunlock", else: "bumplock"}/#{post.id}"
        :lock -> "#{board.uri}/#{if post.locked, do: "unlock", else: "lock"}/#{post.id}"
        :move -> "#{board.uri}/#{if thread_op?(post), do: "move", else: "move_reply"}/#{post.id}"
        :cycle -> "#{board.uri}/#{if post.cycle, do: "uncycle", else: "cycle"}/#{post.id}"
        :editpost -> "#{board.uri}/edit/#{post.id}"
      end

    href = "/mod.php?/" <> action_path

    secure_href =
      case action do
        act
        when act in [:delete, :deletebyip, :deletebyip_global, :sticky, :bumplock, :lock, :cycle] ->
          token = ManageSecurity.sign_action(session_token, action_path)
          href <> "/#{token}"

        _ ->
          href
      end

    %{
      href: href,
      secure: secure_href,
      title: control_title(post, action),
      label: control_label(post, action),
      confirm: control_confirm(action)
    }
  end

  defp control_title(_post, :delete), do: "Delete"
  defp control_title(_post, :deletebyip), do: "Delete all posts by IP"
  defp control_title(_post, :deletebyip_global), do: "Delete all posts by IP across all boards"
  defp control_title(_post, :ban), do: "Ban"
  defp control_title(_post, :bandelete), do: "Ban & Delete"

  defp control_title(post, :sticky),
    do: if(post.sticky, do: "Make thread not sticky", else: "Make thread sticky")

  defp control_title(post, :bumplock),
    do: if(post.sage, do: "Allow thread to be bumped", else: "Prevent thread from being bumped")

  defp control_title(post, :lock), do: if(post.locked, do: "Unlock thread", else: "Lock thread")

  defp control_title(post, :move),
    do:
      if(thread_op?(post), do: "Move thread to another board", else: "Move reply to another board")

  defp control_title(post, :cycle),
    do: if(post.cycle, do: "Make thread not cycle", else: "Make thread cycle")

  defp control_title(_post, :editpost), do: "Edit post"

  defp control_label(_post, :delete), do: "[D]"
  defp control_label(_post, :deletebyip), do: "[D+]"
  defp control_label(_post, :deletebyip_global), do: "[D++]"
  defp control_label(_post, :ban), do: "[B]"
  defp control_label(_post, :bandelete), do: "[B&D]"
  defp control_label(post, :sticky), do: if(post.sticky, do: "[-Sticky]", else: "[Sticky]")
  defp control_label(post, :bumplock), do: if(post.sage, do: "[-Sage]", else: "[Sage]")
  defp control_label(post, :lock), do: if(post.locked, do: "[-Lock]", else: "[Lock]")
  defp control_label(_post, :move), do: "[Move]"
  defp control_label(post, :cycle), do: if(post.cycle, do: "[-Cycle]", else: "[Cycle]")
  defp control_label(_post, :editpost), do: "[Edit]"

  defp control_confirm(:delete), do: "Are you sure you want to delete this?"

  defp control_confirm(:deletebyip),
    do: "Are you sure you want to delete all posts by this IP address?"

  defp control_confirm(:deletebyip_global),
    do: "Are you sure you want to delete all posts by this IP address, across all boards?"

  defp control_confirm(:sticky),
    do: "Are you sure you want to change sticky state for this thread?"

  defp control_confirm(:bumplock),
    do: "Are you sure you want to change bump lock state for this thread?"

  defp control_confirm(:lock), do: "Are you sure you want to change lock state for this thread?"
  defp control_confirm(:cycle), do: "Are you sure you want to change cycle state for this thread?"
  defp control_confirm(_action), do: ""

  defp file_control_metadata(post, file, board, session_token, :deletefile) do
    file_index = file_index(post, file)
    action_path = "#{board.uri}/deletefile/#{post.id}/#{file_index}"
    href = "/mod.php?/" <> action_path
    token = ManageSecurity.sign_action(session_token, action_path)

    %{
      href: href,
      secure: href <> "/#{token}",
      title: "Delete file",
      label: "[F]",
      confirm: "Are you sure you want to delete this file?"
    }
  end

  defp file_control_metadata(post, file, board, session_token, :spoilerimage) do
    file_index = file_index(post, file)
    action_path = "#{board.uri}/spoiler/#{post.id}/#{file_index}"
    href = "/mod.php?/" <> action_path
    token = ManageSecurity.sign_action(session_token, action_path)

    %{
      href: href,
      secure: href <> "/#{token}",
      title: "Spoiler file",
      label: "[S]",
      confirm: "Are you sure you want to spoiler this file?"
    }
  end

  defp file_confirm_control(post, file, board, session_token, action) do
    %{href: href, secure: secure_href, title: title, label: label, confirm: message} =
      file_control_metadata(post, file, board, session_token, action)

    ~s|<a onclick="if (event.which==2) return true;if (confirm('#{js_escape(message)}')) document.location='#{html_escape_to_string(secure_href)}';return false;" title="#{html_escape_to_string(title)}" href="#{html_escape_to_string(href)}">#{label}</a>|
  end

  defp maybe_add_control(list, true, html) when is_binary(html), do: list ++ [html]
  defp maybe_add_control(list, _condition, _html), do: list

  defp thread_op?(post), do: is_nil(post.thread_id)

  defp js_escape(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
  end

  defp file_count(%{file_path: nil} = post), do: length(extra_files(post))
  defp file_count(post), do: 1 + length(extra_files(post))
  defp media_count(post), do: file_count(post) + if(has_embed?(post), do: 1, else: 0)

  defp file_index(_post, %PostFile{position: position}) when is_integer(position), do: position

  defp file_index(post, file) do
    if Map.get(file, :file_path) == post.file_path, do: 0, else: 0
  end

  defp flag_path(code, config) when is_binary(code) do
    config.uri_flags
    |> normalize_flag_base_path()
    |> String.replace("%s", code)
  end

  defp flag_path(_code, _config), do: nil

  defp normalize_flag_base_path(path) when is_binary(path) do
    trimmed = String.trim(path)

    cond do
      trimmed == "" -> trimmed
      String.starts_with?(trimmed, ["/", "http://", "https://", "../", "./"]) -> trimmed
      true -> "/" <> trimmed
    end
  end

  defp maybe_add_icon(icons, true, path, title) when is_binary(path) and path != "" do
    icons ++ [%{path: path, title: title}]
  end

  defp maybe_add_icon(icons, _enabled, _path, _title), do: icons

  defp maybe_add_omitted(parts, count, label) when is_integer(count) and count > 0 do
    parts ++ ["#{count} #{label}"]
  end

  defp maybe_add_omitted(parts, _count, _label), do: parts

  defp format_body_line(line, board, thread, config) do
    rendered =
      line
      |> render_quote_links(board, thread, config)
      |> WhaleStickers.replace_line(config)

    if String.starts_with?(rendered, "&gt;") and not String.starts_with?(rendered, "&gt;&gt;") do
      ~s(<span class="quote">#{rendered}</span>)
    else
      rendered
    end
  end

  defp render_quote_links(line, board, thread, config) do
    Regex.replace(~r/&gt;&gt;(\d+)/, line, fn _match, id ->
      href = ThreadPaths.thread_path(board, thread, config) <> "##{id}"
      "<a onclick=\"highlightReply('#{id}', event);\" href=\"#{href}\">&gt;&gt;#{id}</a>"
    end)
  end

  defp normalize_embedding_rule([pattern, html]) when is_binary(html),
    do: compile_embedding_regex(pattern, html)

  defp normalize_embedding_rule(%{"pattern" => pattern, "html" => html}),
    do: compile_embedding_regex(pattern, html)

  defp normalize_embedding_rule(%{pattern: pattern, html: html}),
    do: compile_embedding_regex(pattern, html)

  defp normalize_embedding_rule(_rule), do: :error

  defp compile_embedding_regex(%Regex{} = regex, html), do: {:ok, regex, html}

  defp compile_embedding_regex(pattern, html) when is_binary(pattern) and is_binary(html) do
    case Regex.run(~r{\A/(.*)/([a-z]*)\z}s, pattern, capture: :all_but_first) do
      [source, modifiers] ->
        case Regex.compile(source, regex_options(modifiers)) do
          {:ok, regex} -> {:ok, regex, html}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp compile_embedding_regex(_pattern, _html), do: :error

  defp regex_options(modifiers) do
    modifiers
    |> String.graphemes()
    |> Enum.reduce("", fn
      "i", acc -> acc <> "i"
      "m", acc -> acc <> "m"
      "s", acc -> acc <> "s"
      "u", acc -> acc <> "u"
      _, acc -> acc
    end)
  end

  defp apply_embedding_template(template, captures, config) do
    rendered =
      captures
      |> Enum.with_index()
      |> Enum.reduce(template, fn {value, index}, acc ->
        String.replace(acc, "$#{index}", value || "")
      end)

    rendered
    |> String.replace("%%tb_width%%", to_string(Map.get(config, :embed_width, 300)))
    |> String.replace("%%tb_height%%", to_string(Map.get(config, :embed_height, 246)))
  end

  defp youtube_thumbnail(embed) do
    case Regex.run(
           ~r/^https?:\/\/(\w+\.)?(?:youtube\.com\/watch\?v=|youtu\.be\/)([a-zA-Z0-9\-_]{10,11})(&.+)?$/i,
           embed
         ) do
      [_, _prefix, video_id | _rest] -> "//img.youtube.com/vi/#{video_id}/0.jpg"
      _ -> nil
    end
  end

  defp html_escape_to_string(value) do
    value
    |> to_string()
    |> html_escape()
    |> safe_to_string()
  end

  defp human_file_size(size) when is_integer(size) and size >= 1_048_576 do
    "#{Float.round(size / 1_048_576, 2)} MB"
  end

  defp human_file_size(size) when is_integer(size) and size >= 1024 do
    "#{Float.round(size / 1024, 1)} KB"
  end

  defp human_file_size(size) when is_integer(size) and size >= 0, do: "#{size} B"
  defp human_file_size(_size), do: nil

  defp blank_fragment?(nil), do: true
  defp blank_fragment?(""), do: true
  defp blank_fragment?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank_fragment?(_value), do: false

  defp dimensions(%{image_width: width, image_height: height})
       when is_integer(width) and is_integer(height),
       do: "#{width}x#{height}"

  defp dimensions(_file), do: nil

  defp original_file_name_detail(file, config) do
    original = original_file_name(file)
    stored = stored_file_name(file)
    limit = max(Map.get(config, :max_filename_display_length, 30), 1)

    cond do
      original in [nil, "", stored] ->
        nil

      String.length(original) > limit ->
        String.slice(original, 0, limit) <> "..."

      true ->
        original
    end
  end

  defp fit_dimensions(width, height, max_width, max_height)
       when is_integer(width) and width > 0 and is_integer(height) and height > 0 and
              is_integer(max_width) and max_width > 0 and is_integer(max_height) and
              max_height > 0 do
    scale = min(max_width / width, max_height / height)
    scale = min(scale, 1.0)
    {max(trunc(Float.floor(width * scale)), 1), max(trunc(Float.floor(height * scale)), 1)}
  end

  defp fit_dimensions(_width, _height, _max_width, _max_height), do: nil

  defp normalize_string(nil), do: nil
  defp normalize_string(value) when is_binary(value), do: String.trim(value)

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)
end
