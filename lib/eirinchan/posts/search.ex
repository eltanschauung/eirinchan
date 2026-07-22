defmodule Eirinchan.Posts.Search do
  @moduledoc false

  import Ecto.Query

  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Posts.{Post, PostFile}
  alias Eirinchan.Repo

  @legacy_filters ~w(id thread subject name)
  @text_fields ~w(text subject username tripcode email uid country filename image_hash)
  @flag_aliases %{"canada" => "ca"}

  @spec normalize_criteria(map()) :: map()
  def normalize_criteria(params) when is_map(params) do
    text = value(params, "text") || value(params, "search") || value(params, "q") || ""
    {text, legacy} = extract_legacy_filters(text)

    %{
      text: text,
      thread: first_present(value(params, "thread"), value(params, "tnum"), legacy["thread"]),
      post_id: first_present(value(params, "post_id"), legacy["id"]),
      subject: first_present(value(params, "subject"), legacy["subject"]),
      username: first_present(value(params, "username"), value(params, "name"), legacy["name"]),
      tripcode: value(params, "tripcode"),
      email: value(params, "email"),
      uid: value(params, "uid"),
      country: value(params, "country") |> normalize_country(),
      filename: value(params, "filename"),
      image_hash:
        first_present(value(params, "image_hash"), value(params, "imagehash"))
        |> normalize_image_hash(),
      width: positive_integer(value(params, "width")),
      height: positive_integer(value(params, "height")),
      start_date: date(value(params, "start")),
      end_date: date(value(params, "end")),
      image: allowed(value(params, "image"), ~w(all with without spoiler nonspoiler), "all"),
      type: allowed(value(params, "type"), ~w(all sticky op reply), "all"),
      results: allowed(value(params, "results"), ~w(posts threads), "posts"),
      order: allowed(value(params, "order"), ~w(latest oldest), "latest"),
      highlight: truthy?(value(params, "highlight"))
    }
  end

  @spec meaningful?(map()) :: boolean()
  def meaningful?(criteria) do
    Enum.any?(@text_fields, &present?(Map.get(criteria, String.to_existing_atom(&1)))) or
      present?(criteria.thread) or present?(criteria.post_id) or criteria.width != nil or
      criteria.height != nil or criteria.start_date != nil or criteria.end_date != nil or
      criteria.image != "all" or criteria.type != "all"
  end

  @spec term_count(map()) :: non_neg_integer()
  def term_count(criteria) do
    @text_fields
    |> Enum.flat_map(fn
      "country" -> flag_codes(criteria.country)
      field -> tokenize(Map.get(criteria, String.to_existing_atom(field)))
    end)
    |> length()
  end

  @spec run([BoardRecord.t()], map(), keyword()) :: {:ok, map()} | {:error, :unavailable}
  def run(boards, criteria, opts \\ []) when is_list(boards) do
    repo = Keyword.get(opts, :repo, Repo)
    page_size = positive_option(opts[:page_size], 25)
    max_matches = positive_option(opts[:max_matches], 5_000)
    timeout = positive_option(opts[:timeout], 3_000)
    requested_page = positive_option(opts[:page], 1)
    board_ids = Enum.map(boards, & &1.id)

    try do
      query =
        from(post in Post, where: post.board_id in ^board_ids)
        |> apply_text(criteria.text)
        |> apply_public_id(criteria.post_id)
        |> apply_thread(criteria.thread, board_ids)
        |> apply_text_field(:subject, criteria.subject)
        |> apply_text_field(:name, criteria.username)
        |> apply_text_field(:tripcode, criteria.tripcode)
        |> apply_text_field(:email, criteria.email)
        |> apply_text_field(:poster_id, criteria.uid)
        |> apply_country(criteria.country)
        |> apply_filename(criteria.filename)
        |> apply_image_hash(criteria.image_hash)
        |> apply_dimensions(criteria.width, criteria.height)
        |> apply_dates(criteria.start_date, criteria.end_date)
        |> apply_image_filter(criteria.image)
        |> apply_post_type(criteria.type)

      ids =
        query
        |> ordered_ids(criteria.order, criteria.results)
        |> limit(^(max_matches + 1))
        |> repo.all(timeout: timeout)

      capped? = length(ids) > max_matches
      ids = Enum.take(ids, max_matches)
      total = length(ids)
      total_pages = max(ceil_div(total, page_size), 1)
      page = min(requested_page, total_pages)
      page_ids = ids |> Enum.drop((page - 1) * page_size) |> Enum.take(page_size)
      positions = page_ids |> Enum.with_index() |> Map.new()

      posts =
        if page_ids == [] do
          []
        else
          repo.all(from(post in Post, where: post.id in ^page_ids), timeout: timeout)
          |> repo.preload([:board, :thread, :extra_files])
          |> Enum.sort_by(&Map.fetch!(positions, &1.id))
        end

      {:ok,
       %{
         posts: posts,
         total: total,
         capped?: capped?,
         page: page,
         page_size: page_size,
         total_pages: total_pages
       }}
    rescue
      _error in [DBConnection.ConnectionError, Postgrex.Error] -> {:error, :unavailable}
    end
  end

  defp apply_text(query, value) do
    Enum.reduce(patterns(value), query, fn pattern, scoped ->
      from post in scoped, where: ilike(post.body, ^pattern)
    end)
  end

  defp apply_public_id(query, value) do
    case integer(value) do
      nil -> query
      public_id -> from post in query, where: post.public_id == ^public_id
    end
  end

  defp apply_thread(query, value, board_ids) do
    case integer(value) do
      nil ->
        query

      public_id ->
        thread_ids =
          from thread in Post,
            where: thread.board_id in ^board_ids and thread.public_id == ^public_id,
            select: thread.id

        from post in query,
          where: post.id in subquery(thread_ids) or post.thread_id in subquery(thread_ids)
    end
  end

  defp apply_text_field(query, _field, value) when value in [nil, ""], do: query

  defp apply_text_field(query, field_name, value) do
    Enum.reduce(patterns(value), query, fn pattern, scoped ->
      from post in scoped, where: ilike(field(post, ^field_name), ^pattern)
    end)
  end

  defp apply_country(query, nil), do: query

  defp apply_country(query, country) do
    flags = flag_codes(country)

    from post in query,
      where: fragment("? @> ?", post.flag_codes, type(^flags, {:array, :string}))
  end

  defp apply_filename(query, value) do
    Enum.reduce(patterns(value), query, fn pattern, scoped ->
      extra_ids =
        from file in PostFile,
          where: ilike(file.file_name, ^pattern),
          select: file.post_id

      from post in scoped,
        where: ilike(post.file_name, ^pattern) or post.id in subquery(extra_ids)
    end)
  end

  defp apply_image_hash(query, nil), do: query

  defp apply_image_hash(query, hash) do
    extra_ids = from file in PostFile, where: file.file_md5 == ^hash, select: file.post_id
    from post in query, where: post.file_md5 == ^hash or post.id in subquery(extra_ids)
  end

  defp apply_dimensions(query, nil, nil), do: query

  defp apply_dimensions(query, width, nil) do
    extra_ids =
      from file in PostFile, where: file.image_width == ^width, select: file.post_id

    from post in query, where: post.image_width == ^width or post.id in subquery(extra_ids)
  end

  defp apply_dimensions(query, nil, height) do
    extra_ids =
      from file in PostFile, where: file.image_height == ^height, select: file.post_id

    from post in query, where: post.image_height == ^height or post.id in subquery(extra_ids)
  end

  defp apply_dimensions(query, width, height) do
    extra_ids =
      from file in PostFile,
        where: file.image_width == ^width and file.image_height == ^height,
        select: file.post_id

    from post in query,
      where:
        (post.image_width == ^width and post.image_height == ^height) or
          post.id in subquery(extra_ids)
  end

  defp apply_dates(query, start_date, end_date) do
    query =
      case start_date do
        %Date{} = date ->
          from post in query,
            where: post.inserted_at >= ^DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

        _ ->
          query
      end

    case end_date do
      %Date{} = date ->
        cutoff = date |> Date.add(1) |> DateTime.new!(~T[00:00:00], "Etc/UTC")
        from post in query, where: post.inserted_at < ^cutoff

      _ ->
        query
    end
  end

  defp apply_image_filter(query, "with"), do: with_any_image(query)

  defp apply_image_filter(query, "without") do
    extra_ids = from file in PostFile, where: file.file_path != "deleted", select: file.post_id

    from post in query,
      where:
        (is_nil(post.file_path) or post.file_path == "deleted") and
          post.id not in subquery(extra_ids)
  end

  defp apply_image_filter(query, "spoiler") do
    extra_ids =
      from file in PostFile,
        where: file.file_path != "deleted" and file.spoiler == true,
        select: file.post_id

    from post in query,
      where:
        (post.file_path != "deleted" and post.spoiler == true) or post.id in subquery(extra_ids)
  end

  defp apply_image_filter(query, "nonspoiler") do
    extra_ids =
      from file in PostFile,
        where: file.file_path != "deleted" and file.spoiler == false,
        select: file.post_id

    from post in query,
      where:
        (post.file_path != "deleted" and not is_nil(post.file_path) and post.spoiler == false) or
          post.id in subquery(extra_ids)
  end

  defp apply_image_filter(query, _), do: query

  defp with_any_image(query) do
    extra_ids = from file in PostFile, where: file.file_path != "deleted", select: file.post_id

    from post in query,
      where:
        (not is_nil(post.file_path) and post.file_path != "deleted") or
          post.id in subquery(extra_ids)
  end

  defp apply_post_type(query, "sticky"),
    do: from(post in query, where: is_nil(post.thread_id) and post.sticky == true)

  defp apply_post_type(query, "op"), do: from(post in query, where: is_nil(post.thread_id))
  defp apply_post_type(query, "reply"), do: from(post in query, where: not is_nil(post.thread_id))
  defp apply_post_type(query, _), do: query

  defp ordered_ids(query, order, "threads") do
    direction = if order == "oldest", do: :asc, else: :desc

    distinct_rows =
      query
      |> exclude(:order_by)
      |> distinct([post], fragment("coalesce(?, ?)", post.thread_id, post.id))
      |> order_by([post], [
        fragment("coalesce(?, ?)", post.thread_id, post.id),
        {^direction, post.inserted_at},
        {^direction, post.id}
      ])
      |> select([post], %{id: post.id, inserted_at: post.inserted_at})

    from row in subquery(distinct_rows),
      order_by: [{^direction, row.inserted_at}, {^direction, row.id}],
      select: row.id
  end

  defp ordered_ids(query, order, _results) do
    direction = if order == "oldest", do: :asc, else: :desc

    from post in query,
      order_by: [{^direction, post.inserted_at}, {^direction, post.id}],
      select: post.id
  end

  defp extract_legacy_filters(value) do
    pattern = ~r/(^|\s)(\w+):("([^"]*)"|[^\s]*)/u

    Regex.scan(pattern, value)
    |> Enum.reduce({value, %{}}, fn [whole, _prefix, name, raw | rest], {text, filters} ->
      name = String.downcase(name)
      quoted = List.first(rest)

      if name in @legacy_filters do
        parsed = if quoted in [nil, ""], do: String.trim(raw, "\""), else: quoted
        {String.replace(text, whole, " ", global: false), Map.put(filters, name, parsed)}
      else
        {text, filters}
      end
    end)
    |> then(fn {text, filters} -> {String.trim(text), filters} end)
  end

  defp patterns(value), do: value |> tokenize() |> Enum.map(&wildcard_pattern/1)

  defp tokenize(nil), do: []

  defp tokenize(value) do
    Regex.scan(~r/"([^"]+)"|(\S+)/u, to_string(value), capture: :all_but_first)
    |> Enum.map(&Enum.find(&1, fn part -> part not in [nil, ""] end))
    |> Enum.reject(&is_nil/1)
  end

  defp wildcard_pattern(term) do
    escaped =
      term
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")
      |> String.replace("*", "%")
      |> String.replace("?", "_")

    "%#{escaped}%"
  end

  defp value(params, key), do: params |> Map.get(key) |> trim()
  defp trim(nil), do: nil
  defp trim(value) when is_binary(value), do: value |> String.trim() |> blank_to_nil()
  defp trim(value), do: value |> to_string() |> String.trim() |> blank_to_nil()
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
  defp first_present(a, b, c \\ nil), do: Enum.find([a, b, c], &present?/1)
  defp present?(value), do: value not in [nil, ""]

  defp positive_integer(value) do
    case integer(value) do
      number when is_integer(number) and number > 0 -> number
      _ -> nil
    end
  end

  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp integer(_), do: nil
  defp positive_option(value, default), do: positive_integer(value) || default

  defp date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp date(_), do: nil
  defp normalize_country(nil), do: nil

  defp normalize_country(value) do
    case flag_codes(value) do
      [] -> nil
      flags -> Enum.join(flags, ",")
    end
  end

  defp flag_codes(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
    |> Enum.map(&Map.get(@flag_aliases, &1, &1))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp flag_codes(_value), do: []

  defp normalize_image_hash(hash) when is_binary(hash) and byte_size(hash) == 24 do
    with {:ok, decoded} <- Base.decode64(hash),
         true <- byte_size(decoded) == 16,
         true <- Base.encode64(decoded) == hash do
      hash
    else
      _ -> nil
    end
  end

  defp normalize_image_hash(_hash), do: nil
  defp allowed(value, allowed, default), do: if(value in allowed, do: value, else: default)
  defp truthy?(value), do: value in [true, "true", "1", "on", "yes"]
  defp ceil_div(0, _denominator), do: 0
  defp ceil_div(numerator, denominator), do: div(numerator + denominator - 1, denominator)
end
