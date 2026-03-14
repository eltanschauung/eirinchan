defmodule Eirinchan.Posts.PublicIds do
  @moduledoc false

  alias Eirinchan.Posts.Post

  def public_id(%Post{public_id: public_id}) when is_integer(public_id), do: public_id
  def public_id(%{public_id: public_id}) when is_integer(public_id), do: public_id
  def public_id(%Post{id: id}), do: id
  def public_id(%{id: id}) when is_integer(id), do: id

  def thread_public_id(%Post{thread_id: nil} = thread), do: public_id(thread)
  def thread_public_id(%{thread_id: nil} = thread), do: public_id(thread)
  def thread_public_id(%{} = post), do: thread_public_id(post, nil)

  def thread_public_id(%{thread: %Ecto.Association.NotLoaded{}, thread_public_id: public_id}, nil)
      when is_integer(public_id),
      do: public_id

  def thread_public_id(%{thread: %Ecto.Association.NotLoaded{}, thread_id: thread_id}, nil)
      when is_integer(thread_id),
      do: thread_id

  def thread_public_id(%{thread: thread}, nil) when not is_nil(thread),
    do: public_id(thread)

  def thread_public_id(%{thread_public_id: public_id}, nil) when is_integer(public_id),
    do: public_id

  def thread_public_id(%{thread_id: thread_id}, nil) when is_integer(thread_id), do: thread_id
  def thread_public_id(_post, %Post{} = thread), do: public_id(thread)
  def thread_public_id(_post, %{public_id: public_id}) when is_integer(public_id), do: public_id

  def ids_by_internal(posts) when is_list(posts) do
    Map.new(posts, fn post -> {Map.fetch!(post, :id), public_id(post)} end)
  end

  def ids_by_public(posts) when is_list(posts) do
    Map.new(posts, fn post -> {public_id(post), Map.fetch!(post, :id)} end)
  end

  def public_set(posts_or_ids) when is_list(posts_or_ids) do
    posts_or_ids
    |> Enum.map(fn
      %{} = post -> public_id(post)
      value when is_integer(value) -> value
    end)
    |> MapSet.new()
  end
end
