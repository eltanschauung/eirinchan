defmodule Eirinchan.Polls.Command do
  @moduledoc "Parses a single /poll command line without invoking a shell."

  def command_line?(line), do: Regex.match?(~r/^\h*\/poll(?:\h|$)/u, line)

  def parse(body) when is_binary(body) do
    lines = String.split(body, ~r/\r\n|\r|\n/, trim: false)

    case Enum.filter(lines, &command_line?/1) do
      [] -> {:ok, nil}
      [line] -> parse_line(line)
      _ -> {:error, :multiple_polls}
    end
  end

  def parse(_), do: {:ok, nil}

  defp parse_line(line) when byte_size(line) > 8_192, do: {:error, :invalid_poll}

  defp parse_line(line) do
    arguments = Regex.replace(~r/^\h*\/poll\h*/u, line, "")

    with {:ok, [question | options]} <- tokens(arguments, []),
         true <- codepoint_length(question) in 1..300,
         true <- length(options) in 2..6,
         true <- Enum.all?(options, &(codepoint_length(&1) in 1..200)),
         true <- length(Enum.uniq_by(options, &String.downcase/1)) == length(options) do
      {:ok, %{question: question, options: options}}
    else
      _ -> {:error, :invalid_poll}
    end
  end

  # PostgreSQL char_length also counts Unicode code points, not grapheme
  # clusters. Validate the same bounds before entering the database transaction.
  defp codepoint_length(value), do: value |> String.codepoints() |> length()

  defp tokens(input, acc) do
    case String.trim_leading(input) do
      "" ->
        {:ok, Enum.reverse(acc)}

      <<?", rest::binary>> ->
        with {:ok, value, tail} <- quoted(rest, []),
             true <- tail == "" or Regex.match?(~r/^\h/u, tail) do
          tokens(tail, [String.trim(value) | acc])
        else
          _ -> {:error, :invalid_poll}
        end

      bare ->
        [value | tail] = String.split(bare, ~r/\h+/u, parts: 2)

        if String.contains?(value, "\"") do
          {:error, :invalid_poll}
        else
          tokens(List.first(tail) || "", [value | acc])
        end
    end
  end

  defp quoted(<<>>, _acc), do: {:error, :invalid_poll}
  defp quoted(<<?", rest::binary>>, acc), do: {:ok, IO.iodata_to_binary(Enum.reverse(acc)), rest}

  defp quoted(<<?\\, char, rest::binary>>, acc) when char in [?", ?\\],
    do: quoted(rest, [<<char>> | acc])

  defp quoted(<<char::utf8, rest::binary>>, acc), do: quoted(rest, [<<char::utf8>> | acc])
end
