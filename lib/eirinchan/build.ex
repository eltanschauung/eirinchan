defmodule Eirinchan.Build do
  @moduledoc """
  Minimal filesystem build pipeline for board index and thread pages.
  """

  alias Eirinchan.Api
  alias Eirinchan.Boards
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.BuildQueue
  alias Eirinchan.Posts
  alias Eirinchan.Purge
  alias Eirinchan.Repo
  alias Eirinchan.Themes
  alias Eirinchan.ThreadPaths
  alias EirinchanWeb.PostView

  @spec rebuild_after_post(BoardRecord.t(), Eirinchan.Posts.Post.t(), keyword()) ::
          :ok | {:error, term()}
  def rebuild_after_post(%BoardRecord{} = board, post, opts \\ []) do
    config = Keyword.fetch!(opts, :config)
    thread_id = post.thread_id || post.id
    dispatch(board, {:thread_and_indexes, thread_id}, Keyword.put(opts, :config, config))
  end

  @spec rebuild_thread_state(BoardRecord.t(), integer(), keyword()) :: :ok | {:error, term()}
  def rebuild_thread_state(%BoardRecord{} = board, thread_id, opts \\ []) do
    config = Keyword.fetch!(opts, :config)
    dispatch(board, {:thread_and_indexes, thread_id}, Keyword.put(opts, :config, config))
  end

  @spec rebuild_after_post_update(BoardRecord.t(), Eirinchan.Posts.Post.t(), keyword()) ::
          :ok | {:error, term()}
  def rebuild_after_post_update(%BoardRecord{} = board, post, opts \\ []) do
    config = Keyword.fetch!(opts, :config)
    thread_id = post.thread_id || post.id
    dispatch(board, {:thread_and_indexes, thread_id}, Keyword.put(opts, :config, config))
  end

  @spec rebuild_after_delete(BoardRecord.t(), tuple(), keyword()) :: :ok | {:error, term()}
  def rebuild_after_delete(%BoardRecord{} = board, {:thread, thread}, opts) do
    config = Keyword.fetch!(opts, :config)
    repo = Keyword.get(opts, :repo)

    remove_thread_outputs(board, thread, config)
    dispatch(board, :indexes, config: config, repo: repo)
  end

  def rebuild_after_delete(%BoardRecord{} = board, {:reply, thread_id}, opts) do
    config = Keyword.fetch!(opts, :config)
    dispatch(board, {:thread_and_indexes, thread_id}, Keyword.put(opts, :config, config))
  end

  def ensure_indexes(%BoardRecord{} = board, opts \\ []) do
    config = Keyword.fetch!(opts, :config)

    if config.generation_strategy == "build_on_load" do
      build_indexes(board, opts)
    else
      :ok
    end
  end

  def ensure_thread(%BoardRecord{} = board, thread_id, opts \\ []) do
    config = Keyword.fetch!(opts, :config)

    if config.generation_strategy == "build_on_load" do
      with :ok <- build_thread(board, thread_id, opts) do
        build_indexes(board, opts)
      end
    else
      :ok
    end
  end

  def rebuild_board(%BoardRecord{} = board, opts \\ []) do
    config = Keyword.fetch!(opts, :config)
    repo = Keyword.get(opts, :repo, Repo)

    {:ok, page_data_list} = Posts.list_page_data(board, config: config, repo: repo)

    Enum.each(page_data_list |> Enum.flat_map(& &1.threads), fn summary ->
      _ = build_thread(board, summary.thread.id, config: config, repo: repo)
    end)

    build_indexes(board, config: config, repo: repo)
  end

  def process_pending(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    board = Keyword.get(opts, :board)
    config = Keyword.fetch!(opts, :config)
    jobs = BuildQueue.list_pending(repo: repo, board_id: board && board.id)

    Enum.reduce(jobs, %{processed: 0}, fn job, acc ->
      if board && job.board_id != board.id do
        acc
      else
        current_board =
          board ||
            (repo || Eirinchan.Repo).get(Eirinchan.Boards.BoardRecord, job.board_id)

        _ =
          case job.kind do
            "thread" -> build_thread(current_board, job.thread_id, config: config, repo: repo)
            "indexes" -> build_indexes(current_board, config: config, repo: repo)
          end

        _ = BuildQueue.mark_done(job, repo: repo)
        %{processed: acc.processed + 1}
      end
    end)
  end

  @spec build_thread(BoardRecord.t(), integer(), keyword()) :: :ok | {:error, term()}
  def build_thread(%BoardRecord{} = board, thread_id, opts \\ []) do
    config = Keyword.fetch!(opts, :config)
    repo = Keyword.get(opts, :repo, Repo)

    case Posts.get_thread_view(board, thread_id, repo: repo) do
      {:ok, summary} ->
        html = render_thread(board, summary, config)

        output_paths =
          summary.thread
          |> thread_output_filenames(config)
          |> Enum.map(&Path.join([board_root(), board.uri, config.dir.res, &1]))

        with :ok <- maybe_write_files(output_paths, html, summary.last_modified, config) do
          if get_in(config, [:api, :enabled]) do
            json_output =
              Path.join([board_root(), board.uri, config.dir.res, "#{summary.thread.id}.json"])

            maybe_write_file(
              json_output,
              Jason.encode!(Api.thread_json(summary)),
              summary.last_modified,
              config
            )
          else
            :ok
          end
        end

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @spec build_indexes(BoardRecord.t(), keyword()) :: :ok | {:error, term()}
  def build_indexes(%BoardRecord{} = board, opts \\ []) do
    config = Keyword.fetch!(opts, :config)
    repo = Keyword.get(opts, :repo, Repo)
    {:ok, page_data_list} = Posts.list_page_data(board, config: config, repo: repo)
    first_page = hd(page_data_list)

    with :ok <- write_index_pages(board, page_data_list, config),
         :ok <- write_catalog_page(board, page_data_list, config),
         :ok <- write_api_pages(board, page_data_list, config) do
      remove_stale_index_pages(board, first_page.total_pages, config)
    end
  end

  @spec board_root() :: String.t()
  def board_root do
    Application.fetch_env!(:eirinchan, :build_output_root)
  end

  defp write_file(path, content, config) do
    path
    |> Path.dirname()
    |> File.mkdir_p!()

    case File.write(path, content) do
      :ok ->
        if config, do: Purge.purge_output_path(path, config, board_root: board_root())
        :ok

      error ->
        error
    end
  end

  defp maybe_write_files(paths, content, modified_at, config) do
    Enum.reduce_while(paths, :ok, fn path, :ok ->
      case maybe_write_file(path, content, modified_at, config) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp maybe_write_file(path, content, _modified_at, config),
    do: write_file(path, content, config)

  defp write_index_pages(board, page_data_list, config) do
    Enum.reduce_while(page_data_list, :ok, fn page_data, :ok ->
      filename =
        if page_data.page == 1 do
          config.file_index
        else
          String.replace(config.file_page, "%d", Integer.to_string(page_data.page))
        end

      html = render_index(board, page_data, config)
      output = Path.join([board_root(), board.uri, filename])
      modified_at = page_last_modified(page_data)

      case maybe_write_file(output, html, modified_at, config) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp write_catalog_page(board, page_data_list, config) do
    if Themes.page_theme_enabled?("catalog") do
      html = render_catalog(board, page_data_list, config)
      output = Path.join([board_root(), board.uri, config.file_catalog])
      maybe_write_file(output, html, pages_last_modified(page_data_list), config)
    else
      File.rm(Path.join([board_root(), board.uri, config.file_catalog]))
      :ok
    end
  end

  defp write_api_pages(_board, _page_data_list, %{api: %{enabled: false}}), do: :ok

  defp write_api_pages(board, page_data_list, config) do
    per_page_results =
      Enum.reduce_while(page_data_list, :ok, fn page_data, :ok ->
        json_path = Path.join([board_root(), board.uri, "#{page_data.page - 1}.json"])
        payload = Jason.encode!(Api.page_json(page_data))

        case maybe_write_file(json_path, payload, page_last_modified(page_data), config) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)

    if Themes.page_theme_enabled?("catalog") do
      with :ok <- per_page_results,
           :ok <-
             maybe_write_file(
               Path.join([board_root(), board.uri, "catalog.json"]),
               Jason.encode!(Api.catalog_json(page_data_list)),
               pages_last_modified(page_data_list),
               config
             ) do
        maybe_write_file(
          Path.join([board_root(), board.uri, "threads.json"]),
          Jason.encode!(Api.catalog_json(page_data_list, threads_page: true)),
          pages_last_modified(page_data_list),
          config
        )
      end
    else
      File.rm(Path.join([board_root(), board.uri, "catalog.json"]))
      File.rm(Path.join([board_root(), board.uri, "threads.json"]))
      per_page_results
    end
  end

  defp dispatch(board, {:thread_and_indexes, thread_id}, opts) do
    config = Keyword.fetch!(opts, :config)
    repo = Keyword.get(opts, :repo)

    case config.generation_strategy do
      "defer" ->
        with {:ok, _thread_job} <-
               BuildQueue.enqueue_thread(board, thread_id, repo: repo, config: config),
             {:ok, _index_job} <- BuildQueue.enqueue_indexes(board, repo: repo, config: config) do
          :ok
        end

      "build_on_load" ->
        :ok

      _ ->
        with :ok <- build_thread(board, thread_id, config: config, repo: repo),
             :ok <- build_indexes(board, config: config, repo: repo) do
          :ok
        end
    end
  end

  defp dispatch(board, :indexes, opts) do
    config = Keyword.fetch!(opts, :config)
    repo = Keyword.get(opts, :repo)

    case config.generation_strategy do
      "defer" ->
        case BuildQueue.enqueue_indexes(board, repo: repo, config: config) do
          {:ok, _job} -> :ok
          error -> error
        end

      "build_on_load" ->
        :ok

      _ ->
        build_indexes(board, config: config, repo: repo)
    end
  end

  defp page_last_modified(%{threads: []}), do: DateTime.utc_now()

  defp page_last_modified(%{threads: threads}),
    do: Enum.max_by(threads, & &1.last_modified).last_modified

  defp pages_last_modified([]), do: DateTime.utc_now()

  defp pages_last_modified(pages) do
    pages
    |> Enum.map(&page_last_modified/1)
    |> Enum.reduce(fn current, acc ->
      if DateTime.compare(current, acc) == :gt, do: current, else: acc
    end)
  end

  defp remove_stale_index_pages(board, total_pages, config) do
    if total_pages < config.max_pages do
      Enum.each((total_pages + 1)..config.max_pages, fn page ->
        filename =
          Path.join([
            board_root(),
            board.uri,
            String.replace(config.file_page, "%d", Integer.to_string(page))
          ])

        json_filename = Path.join([board_root(), board.uri, "#{page - 1}.json"])
        _ = File.rm(filename)
        _ = Purge.purge_output_path(filename, config, board_root: board_root())

        if get_in(config, [:api, :enabled]) do
          _ = File.rm(json_filename)
          _ = Purge.purge_output_path(json_filename, config, board_root: board_root())
        end
      end)
    end

    :ok
  end

  defp render_index(board, page_data, config) do
    boardlist = render_boardlist(Boards.list_boards())

    items =
      Enum.map_join(page_data.threads, "\n", fn summary ->
        title = html_escape(PostView.post_title(board, summary.thread, config))
        body = render_body(summary.thread, board, summary.thread, config)
        media = render_media(summary.thread, config)
        replies = render_preview_replies(summary.replies, board, summary.thread, config)
        omitted = render_omitted(summary)
        thread_path = ThreadPaths.thread_path(board, summary.thread, config)
        badges = render_thread_badges(summary.thread)
        delete_form = render_delete_form(board, summary.thread.id)

        ~s(<article id="p#{summary.thread.id}"><h2><a href="#{thread_path}">#{title}</a></h2>#{badges}#{media}#{render_post_identity(summary.thread)}#{render_fileboard_summary(summary.thread, config)}#{render_post_body(summary.thread, body, config)}#{render_post_flags(summary.thread)}#{render_post_tag(summary.thread, config)}#{delete_form}#{omitted}#{replies}</article>)
      end)

    nav = render_pages(page_data.pages, page_data.page)

    """
    <!doctype html>
    <html>
    <head><meta charset="utf-8"><title>/#{html_escape(board.uri)}/ - #{html_escape(board.title)}</title></head>
    <body>
    <h1>/#{html_escape(board.uri)}/ - #{html_escape(board.title)}</h1>
    #{boardlist}
    #{nav}
    #{items}
    #{nav}
    </body>
    </html>
    """
  end

  defp render_thread(board, summary, config) do
    boardlist = render_boardlist(Boards.list_boards())

    replies_html =
      Enum.map_join(summary.replies, "\n", fn reply ->
        subject = html_escape(PostView.post_title(board, reply, config))
        body = render_body(reply, board, summary.thread, config)
        media = render_media(reply, config)
        delete_form = render_delete_form(board, reply.id)

        ~s(<article id="p#{reply.id}"><h3>#{subject}</h3>#{media}#{render_post_identity(reply)}#{render_fileboard_summary(reply, config)}#{render_post_body(reply, body, config)}#{render_post_flags(reply)}#{render_post_tag(reply, config)}#{delete_form}</article>)
      end)

    """
    <!doctype html>
    <html>
    <head><meta charset="utf-8"><title>/#{html_escape(board.uri)}/ - #{html_escape(PostView.post_title(board, summary.thread, config))}</title></head>
    <body>
    <article id="p#{summary.thread.id}">
    <h1>/#{html_escape(board.uri)}/ - #{html_escape(PostView.post_title(board, summary.thread, config))}</h1>
    #{boardlist}
    #{render_thread_badges(summary.thread)}
    #{render_media(summary.thread, config)}
    #{render_post_identity(summary.thread)}
    #{render_fileboard_summary(summary.thread, config)}
    #{render_post_body(summary.thread, render_body(summary.thread, board, summary.thread, config), config)}
    #{render_post_flags(summary.thread)}
    #{render_post_tag(summary.thread, config)}
    #{render_delete_form(board, summary.thread.id)}
    </article>
    #{replies_html}
    </body>
    </html>
    """
  end

  defp render_catalog(board, page_data_list, config) do
    boardlist = render_boardlist(Boards.list_boards())

    items =
      page_data_list
      |> Enum.flat_map(& &1.threads)
      |> Enum.map_join("\n", fn summary ->
        title = html_escape(PostView.post_title(board, summary.thread, config))
        body = render_body(summary.thread, board, summary.thread, config)
        media = render_media(summary.thread, config)
        thread_path = ThreadPaths.thread_path(board, summary.thread, config)
        badges = render_thread_badges(summary.thread)
        delete_form = render_delete_form(board, summary.thread.id)

        ~s(<article id="catalog-#{summary.thread.id}"><h2><a href="#{thread_path}">#{title}</a></h2>#{badges}#{media}#{render_post_identity(summary.thread)}#{render_fileboard_summary(summary.thread, config)}#{render_post_body(summary.thread, body, config)}#{render_post_flags(summary.thread)}#{render_post_tag(summary.thread, config)}#{delete_form}<p>#{summary.reply_count} replies</p></article>)
      end)

    """
    <!doctype html>
    <html>
    <head><meta charset="utf-8"><title>/#{html_escape(board.uri)}/ - #{html_escape(board.title)} catalog</title></head>
    <body>
    <h1>/#{html_escape(board.uri)}/ - #{html_escape(board.title)}</h1>
    <p><a href="/#{html_escape(board.uri)}">Return</a></p>
    #{boardlist}
    #{items}
    </body>
    </html>
    """
  end

  defp thread_output_filenames(thread, config) do
    canonical = ThreadPaths.thread_filename(thread, config)
    legacy = ThreadPaths.legacy_thread_filename(thread, config)
    Enum.uniq([canonical, legacy])
  end

  defp remove_thread_outputs(board, thread, config) do
    thread
    |> thread_output_filenames(config)
    |> Enum.each(fn filename ->
      path = Path.join([board_root(), board.uri, config.dir.res, filename])
      _ = File.rm(path)
      _ = Purge.purge_output_path(path, config, board_root: board_root())
    end)

    json_path = Path.join([board_root(), board.uri, config.dir.res, "#{thread.id}.json"])
    _ = File.rm(json_path)
    _ = Purge.purge_output_path(json_path, config, board_root: board_root())
    :ok
  end

  defp render_thread_badges(thread) do
    labels =
      []
      |> maybe_add_badge(thread.sticky, "Sticky")
      |> maybe_add_badge(thread.locked, "Locked")
      |> maybe_add_badge(thread.cycle, "Cyclical")
      |> maybe_add_badge(thread.sage, "Bumplocked")

    case labels do
      [] -> ""
      _ -> ~s(<p class="thread-flags">#{Enum.join(labels, " ")}</p>)
    end
  end

  defp maybe_add_badge(labels, true, label), do: labels ++ ["[#{label}]"]
  defp maybe_add_badge(labels, _enabled, _label), do: labels

  defp render_delete_form(board, post_id) do
    ~s(<form class="delete-form" action="/#{board.uri}/post" method="post"><input type="hidden" name="delete_post_id" value="#{post_id}" /><input type="password" name="password" placeholder="Password" /><button type="submit">Delete</button></form>)
  end

  defp render_post_flags(%{flag_alts: flag_alts}) when is_list(flag_alts) and flag_alts != [] do
    ""
  end

  defp render_post_flags(_post), do: ""

  defp render_post_identity(%{name: nil, tripcode: nil}), do: ""

  defp render_post_identity(post) do
    label =
      [post.name, post.tripcode]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&html_escape/1)
      |> Enum.join(" ")

    ~s(<p class="post-identity">#{label}</p>)
  end

  defp render_post_tag(%{tag: nil}, _config), do: ""
  defp render_post_tag(%{tag: ""}, _config), do: ""

  defp render_post_tag(%{tag: tag}, %{allowed_tags: allowed_tags}) when is_map(allowed_tags) do
    label = Map.get(allowed_tags, tag, tag)
    ~s(<p class="post-tag">Tag: #{html_escape(label)}</p>)
  end

  defp render_post_tag(%{tag: tag}, _config) do
    ~s(<p class="post-tag">Tag: #{html_escape(tag)}</p>)
  end

  defp render_preview_replies(replies, board, thread, config) do
    Enum.map_join(replies, "\n", fn reply ->
      body = render_body(reply, board, thread, config)
      media = render_media(reply, config)

      ~s(<div class="reply-preview" id="p#{reply.id}">#{media}#{render_post_identity(reply)}<p>#{body}</p>#{render_post_flags(reply)}#{render_post_tag(reply, %{})}</div>)
    end)
  end

  defp render_post_body(post, body, config) do
    if PostView.show_body?(post, config) do
      ~s(<p>#{body}</p>)
    else
      ""
    end
  end

  defp render_fileboard_summary(post, %{fileboard: true}) do
    if PostView.show_fileboard_summary?(post) do
      ~s(<p class="fileboard-summary">Fileboard: #{html_escape(PostView.fileboard_summary(post))}</p>)
    else
      ""
    end
  end

  defp render_fileboard_summary(_post, _config), do: ""

  defp render_media(post, config) do
    cond do
      PostView.has_embed?(post) ->
        PostView.embed_html(post, config) || ""

      true ->
        post
        |> media_entries()
        |> Enum.map_join("", fn file ->
          full_src = html_escape(file.file_path)
          thumb_src = html_escape(file.thumb_path || file.file_path)
          label = html_escape(file.file_name || Path.basename(file.file_path))

          ~s(<figure class="post-file"><a href="#{full_src}"><img src="#{thumb_src}" alt="#{label}" loading="lazy" /></a><figcaption><a href="#{full_src}">#{label}</a></figcaption></figure>)
        end)
    end
  end

  defp media_entries(%{file_path: nil, extra_files: files}) when is_list(files), do: files
  defp media_entries(%{file_path: nil}), do: []

  defp media_entries(post) do
    [Map.take(post, [:file_name, :file_path, :thumb_path]) | extra_files(post)]
    |> Enum.reject(fn file -> is_nil(file.file_path) end)
  end

  defp extra_files(%{extra_files: %Ecto.Association.NotLoaded{}}), do: []
  defp extra_files(%{extra_files: files}) when is_list(files), do: files
  defp extra_files(_post), do: []

  defp render_omitted(%{omitted_posts: omitted_posts, omitted_images: omitted_images})
       when omitted_posts > 0 do
    suffix =
      if omitted_images > 0 do
        " and #{omitted_images} image replies"
      else
        ""
      end

    ~s(<p class="omitted">#{omitted_posts} posts#{suffix} omitted. Click Reply to view.</p>)
  end

  defp render_omitted(_summary), do: ""

  defp render_pages(pages, current_page) do
    links =
      Enum.map_join(pages, " ", fn page ->
        if page.num == current_page do
          ~s(<strong>#{page.num}</strong>)
        else
          ~s(<a href="#{page.link}">#{page.num}</a>)
        end
      end)

    ~s(<nav class="pages">#{links}</nav>)
  end

  defp render_boardlist(boards) do
    boards
    |> PostView.boardlist_groups()
    |> PostView.boardlist_html()
  end

  defp render_body(post, board, thread, config),
    do: PostView.body_html(post, board, thread, config)

  defp html_escape(nil), do: ""

  defp html_escape(value) do
    value
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
