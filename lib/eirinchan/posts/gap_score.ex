defmodule Eirinchan.Posts.GapScore do
  @moduledoc false

  @spec eligible?(non_neg_integer(), non_neg_integer()) :: boolean()
  def eligible?(reply_count, maximum_replies)
      when is_integer(reply_count) and reply_count >= 0 and is_integer(maximum_replies) do
    reply_count < maximum_replies
  end

  @spec calculate(DateTime.t(), non_neg_integer(), non_neg_integer(), keyword()) ::
          pos_integer()
  def calculate(inserted_at, reply_count, image_count, opts \\ [])
      when is_integer(reply_count) and reply_count >= 0 and is_integer(image_count) and
             image_count >= 0 do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    age_seconds =
      inserted_at
      |> DateTime.diff(now, :second)
      |> Kernel.abs()
      |> max(1)

    ceil(activity_half_units(reply_count, image_count) / (age_seconds / 3_600) * 100)
  end

  # Activity is measured in half-reply units. A thread with no replies gets a
  # half-reply grace weight so it ages out twice as fast as a one-reply thread
  # without being deleted immediately after creation.
  defp activity_half_units(0, 0), do: 1
  defp activity_half_units(reply_count, image_count), do: 2 * (reply_count + image_count * 3)
end
