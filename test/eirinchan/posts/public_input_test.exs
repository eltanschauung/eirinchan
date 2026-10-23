defmodule Eirinchan.Posts.PublicInputTest do
  use ExUnit.Case, async: true

  alias Eirinchan.Posts.{Post, PublicInput}

  test "only explicitly editable schema fields cross the public boundary" do
    attrs = Map.new(Post.__schema__(:fields), &{&1, "untrusted"})
    filtered = PublicInput.filter(attrs, %{})

    assert Enum.sort(Map.keys(filtered)) ==
             Enum.sort(~w(name email subject password body embed tag spoiler))
  end

  test "preserves public form, captcha, custom hidden and multi-upload controls" do
    upload = %Plug.Upload{path: "/unused-test-file", filename: "test.png"}

    attrs = %{
      "thread" => "12",
      "post" => "Reply",
      "user_flag" => "country",
      "flags" => "country",
      "no_country" => "1",
      "antispam_answer" => "four",
      "captcha" => "ok",
      "g-recaptcha-response" => "ok",
      "h-captcha-response" => "ok",
      "custom_hidden" => "hash",
      "file" => upload,
      "file2" => upload,
      "files[]" => [upload],
      "files" => %{"0" => upload},
      "file_url" => "disabled",
      "url" => "disabled"
    }

    assert PublicInput.filter(attrs, %{hidden_input_name: "custom_hidden"}) == attrs
    assert PublicInput.filter(%{"unrecognized" => "value"}, %{}) == %{}
  end

  test "custom hidden field cannot re-enable server-owned or upload-preparation fields" do
    for field <- ["public_id", "file_path", "__upload_entries__", "__upload_metadata__"] do
      assert PublicInput.filter(%{field => "untrusted"}, %{hidden_input_name: field}) == %{}
    end
  end
end
