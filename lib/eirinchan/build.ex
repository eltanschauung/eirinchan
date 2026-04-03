defmodule Eirinchan.Build do
  @moduledoc """
  Minimal filesystem build pipeline for board index and thread pages.
  """

  alias Eirinchan.Api
  alias Eirinchan.Boards
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.BuildQueue
  alias Eirinchan.Locking
  alias Eirinchan.Posts
  alias Eirinchan.Posts.PublicIds
  alias Eirinchan.Purge
  alias Eirinchan.Repo
  alias Eirinchan.Themes
  alias Eirinchan.ThreadPaths
  alias EirinchanWeb.Announcements
  alias EirinchanWeb.{PostComponents, PostView}
  alias EirinchanWeb.FragmentCache

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

    case Posts.get_thread_view_by_internal_id(board, thread_id, repo: repo, config: config) do
      {:ok, summary} ->
        html = render_thread(board, summary, config)

        output_paths =
          thread_output_filenames(summary, config)
          |> Enum.map(&Path.join([board_root(), board.uri, config.dir.res, &1]))

        with :ok <- maybe_write_files(output_paths, html, summary.last_modified, config),
             :ok <- maybe_write_last_posts_thread(board, summary, config) do
          result =
            if get_in(config, [:api, :enabled]) do
              json_output =
                Path.join([board_root(), board.uri, config.dir.res, "#{PublicIds.public_id(summary.thread)}.json"])

              maybe_write_file(
                json_output,
                Jason.encode!(Api.thread_json(summary)),
                summary.last_modified,
                config
              )
            else
              :ok
            end

          case result do
            :ok ->
              FragmentCache.clear()
              :ok

            error ->
              error
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
         :ok <- write_catalog_pages(board, config, repo),
         :ok <- write_api_pages(board, page_data_list, config) do
      FragmentCache.clear()
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

  defp write_catalog_pages(board, config, repo) do
    if Themes.page_theme_enabled?("catalog") do
      catalog_pages = build_catalog_pages(board, config, repo)

      Enum.reduce_while(catalog_pages, :ok, fn page_data, :ok ->
        filename =
          if page_data.page == 1 do
            config.file_catalog
          else
            String.replace(config.file_catalog_page, "%d", Integer.to_string(page_data.page))
          end

        html = render_catalog(board, page_data, config)
        output = Path.join([board_root(), board.uri, filename])

        case maybe_write_file(output, html, page_last_modified(page_data), config) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
      |> case do
        :ok ->
          remove_stale_catalog_pages(board, length(catalog_pages), config)

        error ->
          error
      end
    else
      File.rm(Path.join([board_root(), board.uri, config.file_catalog]))
      remove_stale_catalog_pages(board, 0, config)
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
        with {:ok, _thread_job} <-
               BuildQueue.enqueue_thread(board, thread_id, repo: repo, config: config),
             {:ok, _index_job} <- BuildQueue.enqueue_indexes(board, repo: repo, config: config) do
          drain_async(board, config, repo)
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
        with {:ok, _job} <- BuildQueue.enqueue_indexes(board, repo: repo, config: config) do
          drain_async(board, config, repo)
        end
    end
  end

  defp drain_async(board, config, repo) do
    run_async(fn ->
      Locking.with_exclusive_lock(config, "build_drain:#{board.id}", fn ->
        process_pending(board: board, config: config, repo: repo)
      end)
    end)
  end

  defp run_async(fun) when is_function(fun, 0) do
    if Mix.env() == :test do
      fun.()
    else
      case Task.Supervisor.start_child(Eirinchan.BuildTaskSupervisor, fun) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
        {:error, reason} -> {:error, reason}
      end
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

  defp remove_stale_catalog_pages(board, total_pages, config) do
    stale_paths =
      2..100
      |> Enum.map(fn page ->
        path =
          String.replace(config.file_catalog_page, "%d", Integer.to_string(page))

        Path.join([board_root(), board.uri, path])
      end)
      |> Enum.drop(max(total_pages - 1, 0))

    Enum.each(stale_paths, fn path ->
      if File.exists?(path) do
        File.rm(path)
        Purge.purge_output_path(path, config, board_root: board_root())
      end
    end)

    :ok
  end

  defp render_index(board, page_data, config) do
    boardlist = render_boardlist(Boards.list_boards())
    blotter = render_index_blotter(board, config)

    items =
      Enum.map_join(page_data.threads, "\n", fn summary ->
        title = html_escape(PostView.post_title(board, summary.thread, config))
        media = render_media(summary.thread, config)
        replies = render_preview_replies(summary.replies, board, summary.thread, config)
        omitted = render_omitted(summary)
        thread_path =
          ThreadPaths.thread_path(
            board,
            summary.thread,
            config,
            noko50:
              Map.get_lazy(summary, :has_noko50, fn ->
                Map.get(summary, :reply_count, 0) >= Map.get(config, :noko50_min, 0)
              end)
          )
        badges = render_thread_badges(summary.thread, config)
        delete_form = render_delete_form(board, PublicIds.public_id(summary.thread))

        ~s(<article id="p#{PublicIds.public_id(summary.thread)}"><h2><a href="#{thread_path}">#{title}</a></h2>#{badges}#{media}#{render_post_identity(summary.thread, board, config)}#{render_body_container(summary.thread, board, summary.thread, config)}#{render_post_flags(summary.thread)}#{delete_form}#{omitted}#{replies}</article>)
      end)

    nav = render_pages(page_data, board, config)

    """
    <!doctype html>
    <html>
    <head><meta charset="utf-8"><title>/#{html_escape(board.uri)}/ - #{html_escape(board.title)}</title></head>
    <body>
    <h1>/#{html_escape(board.uri)}/ - #{html_escape(board.title)}</h1>
    #{boardlist}
    #{blotter}
    #{nav}
    #{items}
    #{nav}
    </body>
    </html>
    """
  end

  defp render_index_blotter(board, config) do
    [
      Announcements.news_blotter_html(config),
      Announcements.global_message_html(config, surround_hr: true, board: board)
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp render_thread(board, summary, config) do
    boardlist = render_boardlist(Boards.list_boards())

    replies_html =
      Enum.map_join(summary.replies, "\n", fn reply ->
        subject = html_escape(PostView.post_title(board, reply, config))
        media = render_media(reply, config)
        delete_form = render_delete_form(board, PublicIds.public_id(reply))

        ~s(<article id="p#{PublicIds.public_id(reply)}"><h3>#{subject}</h3>#{media}#{render_post_identity(reply, board, config)}#{render_body_container(reply, board, summary.thread, config)}#{render_post_flags(reply)}#{delete_form}</article>)
      end)

    """
    <!doctype html>
    <html>
    <head><meta charset="utf-8"><title>/#{html_escape(board.uri)}/ - #{html_escape(PostView.post_title(board, summary.thread, config))}</title></head>
    <body>
    <article id="p#{PublicIds.public_id(summary.thread)}">
    <h1>/#{html_escape(board.uri)}/ - #{html_escape(PostView.post_title(board, summary.thread, config))}</h1>
    #{boardlist}
    #{render_thread_badges(summary.thread, config)}
    #{render_media(summary.thread, config)}
    #{render_post_identity(summary.thread, board, config)}
    #{render_body_container(summary.thread, board, summary.thread, config)}
    #{render_post_flags(summary.thread)}
    #{render_delete_form(board, PublicIds.public_id(summary.thread))}
    </article>
    #{replies_html}
    </body>
    </html>
    """
  end

  defp render_catalog(board, page_data, config) do
    boardlist = render_boardlist(Boards.list_boards())
    nav = render_catalog_pages(page_data)

    items =
      page_data.threads
      |> Enum.map_join("\n", fn summary ->
        title = html_escape(PostView.post_title(board, summary.thread, config))
        media = render_media(summary.thread, config)
        thread_path =
          ThreadPaths.thread_path(
            board,
            summary.thread,
            config,
            noko50:
              Map.get_lazy(summary, :has_noko50, fn ->
                Map.get(summary, :reply_count, 0) >= Map.get(config, :noko50_min, 0)
              end)
          )
        badges = render_thread_badges(summary.thread, config)
        delete_form = render_delete_form(board, PublicIds.public_id(summary.thread))

        ~s(<article id="catalog-#{PublicIds.public_id(summary.thread)}"><h2><a href="#{thread_path}">#{title}</a></h2>#{badges}#{media}#{render_post_identity(summary.thread, board, config)}#{render_body_container(summary.thread, board, summary.thread, config)}#{render_post_flags(summary.thread)}#{delete_form}<p>#{summary.reply_count} replies</p></article>)
      end)

    """
    <!doctype html>
    <html>
    <head><meta charset="utf-8"><title>/#{html_escape(board.uri)}/ - #{html_escape(board.title)} catalog</title></head>
    <body>
    <h1>/#{html_escape(board.uri)}/ - #{html_escape(board.title)}</h1>
    <p><a href="/#{html_escape(board.uri)}">Return</a></p>
    #{boardlist}
    #{nav}
    #{items}
    #{nav}
    </body>
    </html>
    """
  end

  defp build_catalog_pages(board, config, repo) do
    case Posts.list_catalog_page(board, 1, config: config, repo: repo) do
      {:ok, first_page} ->
        Enum.map(1..first_page.total_pages, fn page ->
          if page == 1 do
            first_page
          else
            {:ok, data} = Posts.list_catalog_page(board, page, config: config, repo: repo)
            data
          end
        end)

      {:error, :not_found} ->
        []
    end
  end

  defp render_catalog_pages(page_data) do
    PostComponents.catalog_pages_html(%{page_data: page_data})
  end

  defp thread_output_filenames(%{thread: thread}, config) do
    canonical = ThreadPaths.thread_filename(thread, config)
    legacy = ThreadPaths.legacy_thread_filename(thread, config)
    Enum.uniq([canonical, legacy])
  end

  defp remove_thread_outputs(board, thread, config) do
    thread
    |> then(&%{thread: &1})
    |> thread_output_filenames(config)
    |> Enum.each(fn filename ->
      path = Path.join([board_root(), board.uri, config.dir.res, filename])
      _ = File.rm(path)
      _ = Purge.purge_output_path(path, config, board_root: board_root())
    end)

    [config.file_page50, config.file_page50_slug]
    |> Enum.map(fn pattern ->
      pattern
      |> String.replace("%d", Integer.to_string(PublicIds.public_id(thread)))
      |> String.replace("%s", thread.slug || "")
    end)
    |> Enum.uniq()
    |> Enum.each(fn filename ->
      path = Path.join([board_root(), board.uri, config.dir.res, filename])
      _ = File.rm(path)
      _ = Purge.purge_output_path(path, config, board_root: board_root())
    end)

    json_path = Path.join([board_root(), board.uri, config.dir.res, "#{PublicIds.public_id(thread)}.json"])
    _ = File.rm(json_path)
    _ = Purge.purge_output_path(json_path, config, board_root: board_root())
    :ok
  end

  defp maybe_write_last_posts_thread(board, %{has_noko50: false, thread: thread}, config) do
    [config.file_page50, config.file_page50_slug]
    |> Enum.map(fn pattern ->
      pattern
      |> String.replace("%d", Integer.to_string(PublicIds.public_id(thread)))
      |> String.replace("%s", thread.slug || "")
    end)
    |> Enum.uniq()
    |> Enum.each(fn filename ->
      path = Path.join([board_root(), board.uri, config.dir.res, filename])
      _ = File.rm(path)
      _ = Purge.purge_output_path(path, config, board_root: board_root())
    end)

    :ok
  end

  defp maybe_write_last_posts_thread(board, %{has_noko50: true, thread: thread} = summary, config) do
    html =
      board
      |> Posts.get_thread_view_by_internal_id(thread.id, config: config, last_posts: true)
      |> case do
        {:ok, last_summary} -> render_thread(board, last_summary, config)
        _ -> nil
      end

    if html do
      output_paths =
        [
          ThreadPaths.thread_filename(thread, config, noko50: true)
        ]
        |> Enum.uniq()
        |> Enum.map(&Path.join([board_root(), board.uri, config.dir.res, &1]))

      maybe_write_files(output_paths, html, summary.last_modified, config)
    else
      :ok
    end
  end

  defp render_thread_badges(thread, config) do
    labels =
      []
      |> maybe_add_badge(thread.sticky, "Sticky")
      |> maybe_add_badge(thread.locked, "Locked")
      |> maybe_add_badge(thread.cycle, "Cyclical")
      |> maybe_add_badge(thread.inactive and config.early_404_gap, "Gap soon")
      |> maybe_add_badge(thread.sage, "Bumplocked")

    case labels do
      [] -> ""
      _ -> ~s(<p class="thread-flags">#{Enum.join(labels, " ")}</p>)
    end
  end

  defp maybe_add_badge(labels, true, label), do: labels ++ ["[#{label}]"]
  defp maybe_add_badge(labels, _enabled, _label), do: labels

  defp render_delete_form(board, post_id) do
    ~s(<form class="delete-form" action="/#{board.uri}/post" method="post"><input type="hidden" name="delete_post_id" value="#{post_id}" /><input type="password" name="password" placeholder="Password" autocomplete="off" /><button type="submit">Delete</button></form>)
  end

  defp render_post_flags(%{flag_alts: flag_alts}) when is_list(flag_alts) and flag_alts != [] do
    ""
  end

  defp render_post_flags(_post), do: ""

  defp render_post_identity(post, board, config) do
    PostComponents.post_identity_html(%{
      post: post,
      board: board,
      config: config
    })
  end

  defp render_preview_replies(replies, board, thread, config) do
    Enum.map_join(replies, "\n", fn reply ->
      PostComponents.reply_preview_html(%{
        post: reply,
        board: board,
        thread: thread,
        config: config
      })
    end)
  end

  defp render_media(post, config) do
    PostView.media_entries(post, config)
    |> Enum.map_join("", fn
      %{kind: :embed, embed_html: embed_html} ->
        embed_html || ""

      file ->
        EirinchanWeb.PostComponents.file_block_html(%{
          post: post,
          file: file,
          config: config
        })
    end)
  end

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

  defp render_pages(page_data, board, config) do
    PostComponents.board_pages_html(%{
      page_data: page_data,
      board_uri: board.uri,
      config: config
    })
  end

  defp render_boardlist(boards) do
    boards
    |> PostView.boardlist_groups(variant: :desktop)
    |> then(&EirinchanWeb.PostComponents.boardlist_html(%{groups: &1}))
  end

  defp render_body_container(post, board, thread, config) do
    PostComponents.body_container_html(%{
      post: post,
      board: board,
      thread: thread,
      config: config,
      hide_fileboard: false
    })
  end

  defp html_escape(nil), do: ""

  defp html_escape(value) do
    value
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
