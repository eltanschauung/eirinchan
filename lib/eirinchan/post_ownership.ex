defmodule Eirinchan.PostOwnership do
  import Ecto.Query, only: [from: 2]

  alias Eirinchan.BrowserIdentity
  alias Eirinchan.PostOwnership.Ownership
  alias Eirinchan.Repo

  def record(browser_identity, post_id)
      when is_binary(browser_identity) and browser_identity != "" and is_integer(post_id) do
    browser_ref = BrowserIdentity.reference(browser_identity)

    %Ownership{}
    |> Ownership.changeset(%{browser_ref: browser_ref, post_id: post_id})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:browser_ref, :post_id])
  end

  def record(_browser_identity, _post_id), do: {:error, :invalid}

  def owned_post_ids(browser_identity, post_ids)
      when is_binary(browser_identity) and browser_identity != "" and is_list(post_ids) do
    browser_ref = BrowserIdentity.reference(browser_identity)

    normalized_ids =
      post_ids
      |> Enum.filter(&is_integer/1)
      |> Enum.uniq()

    if normalized_ids == [] do
      MapSet.new()
    else
      Repo.all(
        from ownership in Ownership,
          where: ownership.browser_ref == ^browser_ref and ownership.post_id in ^normalized_ids,
          select: ownership.post_id
      )
      |> MapSet.new()
    end
  end

  def owned_post_ids(_browser_identity, _post_ids), do: MapSet.new()
end
