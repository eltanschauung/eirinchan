defmodule Eirinchan.PostOwnership do
  import Ecto.Query, only: [from: 2]

  alias Eirinchan.PostOwnership.Ownership
  alias Eirinchan.Repo

  def record(browser_token, post_id)
      when is_binary(browser_token) and browser_token != "" and is_integer(post_id) do
    %Ownership{}
    |> Ownership.changeset(%{browser_token: browser_token, post_id: post_id})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:browser_token, :post_id])
  end

  def record(_browser_token, _post_id), do: {:error, :invalid}

  def owned_post_ids(browser_token, post_ids)
      when is_binary(browser_token) and browser_token != "" and is_list(post_ids) do
    normalized_ids =
      post_ids
      |> Enum.filter(&is_integer/1)
      |> Enum.uniq()

    if normalized_ids == [] do
      MapSet.new()
    else
      Repo.all(
        from ownership in Ownership,
          where: ownership.browser_token == ^browser_token and ownership.post_id in ^normalized_ids,
          select: ownership.post_id
      )
      |> MapSet.new()
    end
  end

  def owned_post_ids(_browser_token, _post_ids), do: MapSet.new()
end
