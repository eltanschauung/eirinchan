defmodule EirinchanWeb.PostHTML do
  @moduledoc """
  HTML responses for public post actions that do not belong to a board page.
  """

  use EirinchanWeb, :html

  embed_templates "post_html/*"

  def ban_reason(%{reason: reason}) when is_binary(reason) do
    case String.trim(reason) do
      "" -> "None"
      trimmed -> trimmed
    end
  end

  def ban_reason(_ban), do: "None"

  def format_ban_datetime(nil), do: "never"

  def format_ban_datetime(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> Calendar.strftime("%m/%d/%y (%a) %H:%M:%S UTC")
  end

  def format_ban_datetime(value), do: to_string(value)

  def appeal_prompt(%{rejected_appeals: []}) do
    "You may appeal this ban. Please enter your reasoning below."
  end

  def appeal_prompt(%{rejected_appeals: [_appeal]}) do
    "You may appeal this ban again. Please enter your reasoning below."
  end

  def appeal_prompt(%{rejected_appeals: appeals}) when is_list(appeals) do
    "You may appeal this ban again. Please enter your reasoning below."
  end

  def appeal_status(%{appeal_error: :appeals_disabled}), do: "Ban appeals are disabled."

  def appeal_status(%{appeal_error: :appeal_too_short}),
    do: "You cannot appeal a ban of this length."

  def appeal_status(%{appeal_error: :appeal_pending, pending_appeal: appeal})
      when not is_nil(appeal) do
    "You submitted an appeal for this ban on #{format_ban_datetime(appeal.inserted_at)}. It is still pending."
  end

  def appeal_status(%{appeal_error: :appeal_limit, rejected_appeals: [appeal]}) do
    "You appealed this ban on #{format_ban_datetime(appeal.inserted_at)} and it was denied. You may not appeal this ban again."
  end

  def appeal_status(%{appeal_error: :appeal_limit}) do
    "You have submitted the maximum number of ban appeals allowed. You may not appeal this ban again."
  end

  def appeal_status(_context), do: nil
end
