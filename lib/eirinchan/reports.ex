defmodule Eirinchan.Reports do
  @moduledoc """
  Minimal report storage and moderation queue.
  """

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Posts.Post
  alias Eirinchan.Repo
  alias Eirinchan.Reports.Report

  @spec create_report(BoardRecord.t(), map(), keyword()) ::
          {:ok, Report.t()} | {:error, :post_not_found | Ecto.Changeset.t()}
  def create_report(%BoardRecord{} = board, attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    attrs = attrs |> normalize_attrs() |> normalize_report_attrs()

    with {:ok, target_post, target_thread_id} <- fetch_target_post(board, attrs, repo),
         {:ok, report} <-
           %Report{}
           |> Report.changeset(%{
             "board_id" => board.id,
             "post_id" => target_post.id,
             "thread_id" => target_thread_id,
             "reason" => Map.get(attrs, "reason")
           })
           |> repo.insert() do
      {:ok, report}
    else
      {:error, :post_not_found} -> {:error, :post_not_found}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  @spec list_reports(BoardRecord.t() | nil, keyword()) :: [Report.t()]
  def list_reports(board \\ nil, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    base =
      from report in Report,
        where: is_nil(report.dismissed_at),
        order_by: [asc: report.inserted_at],
        preload: [:post, :thread, :board]

    query =
      case board do
        %BoardRecord{id: board_id} -> from report in base, where: report.board_id == ^board_id
        nil -> base
      end

    repo.all(query)
  end

  @spec get_report(String.t() | integer(), keyword()) :: Report.t() | nil
  def get_report(report_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    repo.one(
      from report in Report,
        where: report.id == ^normalize_id(report_id),
        preload: [:post, :thread, :board]
    )
  end

  @spec dismiss_report(BoardRecord.t(), String.t() | integer(), keyword()) ::
          {:ok, Report.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def dismiss_report(%BoardRecord{} = board, report_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    case repo.get_by(Report, id: normalize_id(report_id), board_id: board.id) do
      nil ->
        {:error, :not_found}

      report ->
        report
        |> Report.dismiss_changeset(%{
          dismissed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        })
        |> repo.update()
    end
  end

  @spec dismiss_reports_for_post(BoardRecord.t(), String.t() | integer(), keyword()) ::
          {:ok, non_neg_integer()}
  def dismiss_reports_for_post(%BoardRecord{} = board, post_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {count, _} =
      repo.update_all(
        from(
          report in Report,
          where:
            report.board_id == ^board.id and report.post_id == ^normalize_id(post_id) and
              is_nil(report.dismissed_at)
        ),
        set: [dismissed_at: now]
      )

    {:ok, count}
  end

  defp fetch_target_post(board, attrs, repo) do
    case repo.get_by(Post, id: normalize_id(Map.get(attrs, "post_id")), board_id: board.id) do
      nil ->
        {:error, :post_not_found}

      %Post{} = post ->
        {:ok, post, post.thread_id || post.id}
    end
  end

  defp normalize_attrs(attrs) do
    Enum.into(attrs, %{}, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      pair -> pair
    end)
  end

  defp normalize_report_attrs(attrs) do
    case Map.fetch(attrs, "report_post_id") do
      {:ok, post_id} -> Map.put(attrs, "post_id", post_id)
      :error -> attrs
    end
  end

  defp normalize_id(value) when is_integer(value), do: value

  defp normalize_id(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" ->
        nil

      trimmed ->
        case Integer.parse(trimmed) do
          {id, ""} -> id
          _ -> nil
        end
    end
  end

  defp normalize_id(_value), do: nil
end
