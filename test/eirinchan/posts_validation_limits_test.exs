defmodule Eirinchan.PostsValidationLimitsTest do
  use ExUnit.Case, async: true

  alias Eirinchan.Posts.Validation
  alias Eirinchan.Runtime.Config

  test "accepts fields at their configured limits" do
    config = configured_limits()

    assert :ok =
             Validation.validate_body_limits(
               %{
                 "name" => "1234",
                 "email" => "12345",
                 "subject" => "123456",
                 "embed" => "1234567",
                 "password" => "12345678",
                 "body" => "ok"
               },
               config
             )
  end

  test "rejects every oversized public post field" do
    config = configured_limits()

    for {field, value, reason} <- [
          {"name", "12345", :name_too_long},
          {"email", "123456", :email_too_long},
          {"subject", "1234567", :subject_too_long},
          {"embed", "12345678", :embed_too_long},
          {"password", "123456789", :password_too_long}
        ] do
      assert {:error, ^reason} =
               Validation.validate_body_limits(%{field => value, "body" => "ok"}, config)
    end
  end

  defp configured_limits do
    Config.compose(nil, %{
      max_name_length: 4,
      max_email_length: 5,
      max_subject_length: 6,
      max_embed_length: 7,
      post_password_max_length: 8
    })
  end
end
