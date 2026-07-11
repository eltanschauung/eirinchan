defmodule Eirinchan.FeedbackPage do
  @moduledoc false

  alias Eirinchan.LegacyPageBody

  def default_body do
    """
    <p>Submit any kind of feedback you want. Feedback is anonymous.</p>
    """
    |> String.trim()
  end

  def normalize_body(html) do
    LegacyPageBody.normalize(html, &default_body/0, strip: [:style, :header])
  end
end
