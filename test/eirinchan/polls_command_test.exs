defmodule Eirinchan.PollsCommandTest do
  use ExUnit.Case, async: true
  alias Eirinchan.Polls.Command

  test "the requested mixed quoted/unquoted syntax accepts normal surrounding lines" do
    body =
      "Before\n/poll \"What's the meaning of life?\" \"This is option 1\" option2 \"Option three\" option4 option5\nAfter"

    assert {:ok,
            %{
              question: "What's the meaning of life?",
              options: ["This is option 1", "option2", "Option three", "option4", "option5"]
            }} = Command.parse(body)
  end

  test "quoted escapes, Unicode, tabs and CRLF are supported" do
    assert {:ok, %{question: "Say \"hello\"?", options: ["🐳", "c:\\test"]}} =
             Command.parse("text\r\n\t/poll \"Say \\\"hello\\\"?\"\t🐳 \"c:\\\\test\"\r\ntext")
  end

  test "six options are allowed" do
    assert {:ok, %{options: options}} = Command.parse("/poll Q a b c d e f")
    assert length(options) == 6
  end

  for line <- [
        "/poll",
        "/poll Q one",
        "/poll Q a b c d e f g",
        "/poll \"unfinished a b",
        "/poll \"Q\"a b c",
        "/poll Q \"\" b",
        "/poll Q Yes yes",
        "/poll Q a\"b c",
        "/poll \"   \" a b"
      ] do
    test "malformed command #{inspect(line)} is rejected" do
      assert {:error, :invalid_poll} = Command.parse(unquote(line))
    end
  end

  test "question and option lengths are bounded" do
    assert {:error, :invalid_poll} = Command.parse("/poll \"#{String.duplicate("x", 301)}\" a b")
    assert {:error, :invalid_poll} = Command.parse("/poll Q #{String.duplicate("x", 201)} b")
    assert {:error, :invalid_poll} = Command.parse("/poll " <> String.duplicate("x", 8192))
  end

  test "Unicode length limits agree with PostgreSQL rather than rejecting later during insertion" do
    assert {:ok, _} = Command.parse("/poll \"#{String.duplicate("❤️", 150)}\" a b")
    assert {:error, :invalid_poll} = Command.parse("/poll \"#{String.duplicate("❤️", 151)}\" a b")
    assert {:error, :invalid_poll} = Command.parse("/poll Q \"#{String.duplicate("❤️", 101)}\" b")
  end

  test "one poll per post, while quotes and command lookalikes stay ordinary text" do
    assert {:error, :multiple_polls} = Command.parse("/poll Q a b\n/poll R c d")

    for text <- [nil, "hello /poll Q a b", ">/poll Q a b", "/polling Q a b", "/Poll Q a b"] do
      assert {:ok, nil} = Command.parse(text)
    end
  end
end
