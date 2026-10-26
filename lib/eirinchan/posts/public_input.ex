defmodule Eirinchan.Posts.PublicInput do
  @moduledoc false

  alias Eirinchan.Posts.Post

  @fields ~w(name email subject password body embed tag spoiler no_country user_flag flags
             thread post antispam_answer captcha g-recaptcha-response h-captcha-response
             file files files[] file_url url)

  # Only these persisted fields are editable through the public posting form.
  @editable_fields ~w(name email subject password body embed tag spoiler)

  def filter(attrs, config) when is_map(attrs) do
    hidden_name = Map.get(config, :hidden_input_name)
    internal_fields = Enum.map(Post.__schema__(:fields), &Atom.to_string/1) -- @editable_fields

    attrs
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Enum.filter(fn {key, _value} ->
      key not in internal_fields and
        (key in @fields or Regex.match?(~r/\Afile\d+\z/, key) or
           (key == hidden_name and not String.starts_with?(key, "__")))
    end)
    |> Map.new()
  end
end
