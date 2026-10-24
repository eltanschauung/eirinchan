defmodule Eirinchan.CommandOutput do
  @moduledoc false
  defstruct limit: 262_144
end

defimpl Collectable, for: Eirinchan.CommandOutput do
  def into(%{limit: limit}) do
    {{[], 0, false},
     fn
       {chunks, bytes, truncated}, {:cont, chunk} ->
         remaining = max(limit - bytes, 0)
         size = byte_size(chunk)
         kept = min(remaining, size)
         chunks = if kept > 0, do: [binary_part(chunk, 0, kept) | chunks], else: chunks
         {chunks, bytes + kept, truncated or size > remaining}

       {chunks, _bytes, truncated}, :done ->
         {chunks |> Enum.reverse() |> IO.iodata_to_binary(), truncated}

       _state, :halt ->
         :ok
     end}
  end
end
