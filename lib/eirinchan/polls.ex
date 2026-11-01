defmodule Eirinchan.Polls do
  @moduledoc "Single-choice post polls, private vote receipts and atomic admission."
  import Ecto.Query
  alias Eirinchan.{Antispam, BrowserIdentity, CredentialHash, IpMatching, Repo}
  alias Eirinchan.Polls.{Command, Vote}
  alias Eirinchan.Posts.Post

  def attach(attrs) do
    with {:ok, poll} <- Command.parse(Map.get(attrs, "body")) do
      {:ok,
       attrs
       |> Map.put("poll_question", poll && poll.question)
       |> Map.put("poll_options", if(poll, do: poll.options, else: []))}
    end
  end

  def poll?(post),
    do:
      is_binary(Map.get(post, :poll_question)) and
        length(Map.get(post, :poll_options) || []) in 2..6

  def check_creation(attrs, request, config, repo) do
    if is_binary(attrs["poll_question"]) and
         Antispam.configured_public_activity_rate_limited?(request, "poll_create", config,
           repo: repo
         ), do: {:error, :poll_rate_limited}, else: :ok
  end

  # Must run within the same transaction as post allocation/insertion. The
  # shared limiter takes a transaction-scoped lock, including across boards.
  def reserve_creation(attrs, request, config, repo) do
    if is_binary(attrs["poll_question"]) do
      case Antispam.reserve_configured_public_activity("poll_create", request, config, repo: repo) do
        {:ok, _} -> :ok
        {:error, :rate_limited} -> {:error, :poll_rate_limited}
        _ -> {:error, :poll_identity_required}
      end
    else
      :ok
    end
  end

  def validate_edit(post, attrs) do
    if poll?(post) do
      case Command.parse(Map.get(attrs, "body", post.body)) do
        {:ok, %{question: question, options: options}}
        when question == post.poll_question and options == post.poll_options ->
          :ok

        _ ->
          {:error,
           post
           |> Ecto.Changeset.change()
           |> Ecto.Changeset.add_error(
             :body,
             "Poll questions/options cannot be changed or removed; edit surrounding text or delete the post."
           )}
      end
    else
      :ok
    end
  end

  def states(ids, request, opts \\ []) when is_list(ids) and length(ids) <= 50 do
    repo = Keyword.get(opts, :repo, Repo)

    posts =
      repo.all(
        from p in Post,
          where: p.id in ^ids and not is_nil(p.poll_question),
          select: map(p, [:id, :poll_question, :poll_options])
      )

    states_for_posts(posts, request, repo)
  end

  def vote(post_id, choice, request, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    repo.transaction(fn ->
      post =
        repo.one(
          from p in Post,
            where: p.id == ^post_id and not is_nil(p.poll_question),
            select: map(p, [:id, :poll_question, :poll_options]),
            lock: "FOR KEY SHARE"
        )

      if is_nil(post) or not poll?(post), do: repo.rollback(:not_found)

      unless is_integer(choice) and choice >= 0 and choice < length(post.poll_options),
        do: repo.rollback(:invalid_choice)

      {ip_ref, browser_ref} = references(post.id, request)
      if is_nil(ip_ref), do: repo.rollback(:poll_identity_required)

      unless repo.exists?(identity_query([post.id], [ip_ref], List.wrap(browser_ref))) do
        case Antispam.reserve_configured_public_activity("poll_vote", request, %{}, repo: repo) do
          {:ok, _} -> :ok
          {:error, :rate_limited} -> repo.rollback(:rate_limited)
          _ -> repo.rollback(:poll_identity_required)
        end

        case %Vote{}
             |> Vote.changeset(%{
               post_id: post.id,
               choice: choice,
               ip_ref: ip_ref,
               browser_ref: browser_ref
             })
             |> repo.insert(on_conflict: :nothing) do
          {:ok, _} -> :ok
          {:error, _} -> repo.rollback(:not_found)
        end
      end

      states_for_posts([post], request, repo) |> Map.fetch!(post.id)
    end)
  end

  defp states_for_posts(posts, request, repo) do
    refs = Enum.map(posts, &references(&1.id, request))
    ip_refs = refs |> Enum.map(&elem(&1, 0)) |> Enum.reject(&is_nil/1)
    browser_refs = refs |> Enum.map(&elem(&1, 1)) |> Enum.reject(&is_nil/1)
    ids = Enum.map(posts, & &1.id)

    voted =
      repo.all(from v in identity_query(ids, ip_refs, browser_refs), select: v.post_id)
      |> MapSet.new()

    voted_ids = MapSet.to_list(voted)

    counts =
      repo.all(
        from v in Vote,
          where: v.post_id in ^voted_ids,
          group_by: [v.post_id, v.choice],
          select: {v.post_id, v.choice, count(v.id)}
      )
      |> Map.new(fn {post_id, choice, count} -> {{post_id, choice}, count} end)

    Map.new(posts, fn post ->
      state =
        if MapSet.member?(voted, post.id) do
          results =
            post.poll_options
            |> Enum.with_index()
            |> Enum.map(fn {label, choice} ->
              %{label: label, choice: choice, count: Map.get(counts, {post.id, choice}, 0)}
            end)

          %{voted: true, results: results, total: Enum.sum(Enum.map(results, & &1.count))}
        else
          # Not even total counts leave the server before a vote receipt exists.
          %{voted: false}
        end

      {post.id, state}
    end)
  end

  defp identity_query(ids, ips, browsers) do
    from v in Vote, where: v.post_id in ^ids and (v.ip_ref in ^ips or v.browser_ref in ^browsers)
  end

  defp references(post_id, request) do
    ip = Map.get(request, :remote_ip, Map.get(request, "remote_ip"))

    ip_ref =
      case IpMatching.parse_ip(ip) do
        {:ok, parsed} ->
          CredentialHash.fingerprint("#{post_id}\0#{:inet.ntoa(parsed)}", :poll_vote_ip, 43)

        _ ->
          nil
      end

    browser = Map.get(request, :browser_ref, Map.get(request, "browser_ref"))

    browser_ref =
      if is_binary(browser) and browser != "",
        do:
          CredentialHash.fingerprint(
            "#{post_id}\0#{BrowserIdentity.reference(browser)}",
            :poll_vote_browser,
            43
          )

    {ip_ref, browser_ref}
  end
end
