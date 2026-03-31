defmodule Eirinchan.Api do
  @moduledoc """
  Minimal 4chan-style JSON translation for thread/page/catalog artifacts.
  """

  alias Eirinchan.PosterIds
  alias Eirinchan.Posts.PublicIds

  def thread_json(summary, config \\ %{}) do
    %{
      posts: [
        thread_post(summary, config) |
          Enum.map(summary.replies, &reply_post(&1, PublicIds.public_id(summary.thread), config))
      ]
    }
  end

  def boards_json(boards) do
    %{
      boards:
        Enum.map(boards, fn board ->
          %{
            board: board.uri,
            title: board.title,
            ws_board: 1
          }
        end)
    }
  end

  def page_json(page_data, config \\ %{}) do
    %{
      threads: Enum.map(page_data.threads, &thread_json(&1, config))
    }
  end

  def catalog_json(page_data_list, opts \\ []) do
    threads_page? = Keyword.get(opts, :threads_page, false)
    config = Keyword.get(opts, :config, %{})

    Enum.with_index(page_data_list)
    |> Enum.map(fn {page_data, page_index} ->
      %{
        page: page_index,
        threads: Enum.map(page_data.threads, &catalog_thread(&1, threads_page?, config))
      }
    end)
  end

  defp catalog_thread(summary, true, _config) do
      %{
        no: PublicIds.public_id(summary.thread),
        last_modified: unix(summary.last_modified)
      }
  end

  defp catalog_thread(summary, false, config) do
    thread_post(summary, config)
  end

  defp thread_post(summary, config) do
    summary.thread
    |> base_post(0)
    |> maybe_put(:sub, summary.thread.subject)
    |> maybe_put(:com, summary.thread.body)
    |> maybe_put(:embed, summary.thread.embed)
    |> maybe_put(:name, summary.thread.name)
    |> maybe_put_country(summary.thread)
    |> maybe_put_poster_id(summary.thread, config)
    |> Map.put(:time, unix(summary.thread.inserted_at))
    |> Map.put(:replies, summary.reply_count)
    |> Map.put(:images, summary.image_count)
    |> maybe_put_flag(:sticky, summary.thread.sticky)
    |> maybe_put_flag(:closed, summary.thread.locked)
    |> maybe_put_flag(:cyclical, summary.thread.cycle)
    |> maybe_put_flag(:bumplimit, summary.thread.sage)
    |> maybe_put(:semantic_url, summary.thread.slug)
    |> maybe_put(:omitted_posts, positive_or_nil(summary.omitted_posts))
    |> maybe_put(:omitted_images, positive_or_nil(summary.omitted_images))
    |> maybe_put_file(summary.thread)
    |> maybe_put_extra_files(summary.thread)
    |> Map.put(:last_modified, unix(summary.last_modified))
  end

  defp reply_post(post, thread_id, config) do
    post
    |> base_post(thread_id)
    |> maybe_put(:sub, post.subject)
    |> maybe_put(:com, post.body)
    |> maybe_put(:embed, post.embed)
    |> maybe_put(:name, post.name)
    |> maybe_put_country(post)
    |> maybe_put_poster_id(post, config)
    |> maybe_put_file(post)
    |> maybe_put_extra_files(post)
    |> Map.put(:time, unix(post.inserted_at))
  end

  defp base_post(post, resto) do
    %{
      no: PublicIds.public_id(post),
      resto: resto
    }
  end

  defp unix(%DateTime{} = dt), do: DateTime.to_unix(dt)

  defp unix(%NaiveDateTime{} = dt),
    do: dt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_country(map, post) do
    case country_flag(post) do
      {code, name} ->
        map
        |> Map.put(:country, String.upcase(code))
        |> Map.put(:country_name, name)

      nil ->
        map
    end
  end

  defp maybe_put_poster_id(map, post, config) do
    case PosterIds.poster_id(post, config) do
      id when is_binary(id) and id != "" -> Map.put(map, :id, id)
      _ -> map
    end
  end

  defp maybe_put_flag(map, _key, false), do: map
  defp maybe_put_flag(map, _key, nil), do: map
  defp maybe_put_flag(map, key, true), do: Map.put(map, key, 1)

  defp maybe_put_file(map, %{file_path: nil}), do: map

  defp maybe_put_file(map, post) do
    ext = Path.extname(post.file_name || post.file_path || "")
    filename = Path.basename(post.file_name || post.file_path || "", ext)

    map
    |> maybe_put(:filename, filename)
    |> maybe_put(:ext, ext)
    |> maybe_put(:fsize, post.file_size)
    |> maybe_put(:md5, post.file_md5)
    |> maybe_put(:w, post.image_width)
    |> maybe_put(:h, post.image_height)
    |> maybe_put(:tim, post.id)
    |> maybe_put_flag(:spoiler, post.spoiler)
  end

  defp maybe_put_extra_files(map, %{extra_files: %Ecto.Association.NotLoaded{}}), do: map
  defp maybe_put_extra_files(map, %{extra_files: []}), do: map

  defp maybe_put_extra_files(map, %{extra_files: files}) when is_list(files) do
    Map.put(map, :extra_files, Enum.map(files, &extra_file_payload/1))
  end

  defp extra_file_payload(file) do
    ext = Path.extname(file.file_name || file.file_path || "")
    filename = Path.basename(file.file_name || file.file_path || "", ext)

    %{}
    |> maybe_put(:filename, filename)
    |> maybe_put(:ext, ext)
    |> maybe_put(:fsize, file.file_size)
    |> maybe_put(:md5, file.file_md5)
    |> maybe_put(:w, file.image_width)
    |> maybe_put(:h, file.image_height)
    |> maybe_put(:tim, file.id)
    |> maybe_put_flag(:spoiler, file.spoiler)
  end

  defp country_flag(%{flag_codes: flag_codes, flag_alts: flag_alts})
       when is_list(flag_codes) and is_list(flag_alts) do
    Enum.zip(flag_codes, flag_alts)
    |> Enum.find(fn {code, _alt} -> country_code?(code) end)
  end

  defp country_flag(_post), do: nil

  defp country_code?(code) when is_binary(code) do
    String.match?(code, ~r/^[a-z]{2}$/)
  end

  defp country_code?(_code), do: false

  defp positive_or_nil(value) when is_integer(value) and value > 0, do: value
  defp positive_or_nil(_value), do: nil
end
  alias Eirinchan.Posts.PublicIds
