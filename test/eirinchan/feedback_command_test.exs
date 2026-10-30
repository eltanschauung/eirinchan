defmodule Eirinchan.FeedbackCommandTest do
  use ExUnit.Case, async: true
  alias Eirinchan.Feedback.Submission

  test "only an exact command at the beginning is recognized" do
    for body <- ["/feedback text", "/feedback\ntext", "/feedback\ttext", "/feedback"] do
      assert Submission.command?(body)
      assert {:ok, _} = Submission.command_attrs(%{"body" => body})
    end

    for body <- [
          " /feedback text",
          "quoted /feedback text",
          "/feedbackish text",
          "/Feedback text",
          nil,
          []
        ] do
      refute Submission.command?(body)
      assert :not_command = Submission.command_attrs(%{"body" => body})
    end
  end

  test "strips the command and tripcode secret and truncates Unicode at a grapheme boundary" do
    message = String.duplicate("👩‍💻", 2_001)

    assert {:ok, attrs} =
             Submission.command_attrs(%{
               "body" => "/feedback \n" <> message,
               "name" => " Alice##synthetic-test-secret ",
               "email" => "alice@example.invalid",
               "read_at" => "forged",
               "file" => "ignored"
             })

    assert String.length(attrs["body"]) == 2_000
    assert attrs["body"] == String.duplicate("👩‍💻", 2_000)
    assert attrs["name"] == "Alice"
    assert attrs["email"] == "alice@example.invalid"
    assert Enum.sort(Map.keys(attrs)) == ["body", "email", "name"]

    assert {:ok, %{"name" => nil}} =
             Submission.command_attrs(%{"body" => "/feedback text", "name" => "##synthetic-only"})
  end
end
