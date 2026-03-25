defmodule Eirinchan.Posts.RequestGuards do
  @moduledoc false

  alias Eirinchan.AccessList
  alias Eirinchan.Bans
  alias Eirinchan.Captcha
  alias Eirinchan.DNSBL
  alias Eirinchan.Moderation
  alias Eirinchan.Moderation.ModUser
  alias Eirinchan.Posts.Post

  def validate_post_button(true, attrs, config) do
    if valid_post_button?(attrs["post"], config.button_newtopic, ["New Topic", "New Thread"]) do
      :ok
    else
      {:error, :invalid_post_mode}
    end
  end

  def validate_post_button(false, attrs, config) do
    if valid_post_button?(attrs["post"], config.button_reply, ["New Reply", "Reply"]) do
      :ok
    else
      {:error, :invalid_post_mode}
    end
  end

  def validate_referer(_request, %{referer_match: false}, _board), do: :ok

  def validate_referer(request, config, board) do
    if moderator_board_access?(request, board) do
      :ok
    else
      referer = request[:referer] || request["referer"]

      if is_binary(referer) and Regex.match?(config.referer_match, URI.decode(referer)) do
        :ok
      else
        {:error, :invalid_referer}
      end
    end
  end

  def validate_ipaccess(attrs, request, config, board) do
    cond do
      moderator_board_access?(request, board) ->
        :ok

      not Map.get(config, :ipaccess, false) ->
        :ok

      ipaccess_reply_bypass?(attrs, config) ->
        :ok

      ipaccess_bypass?(attrs, config) ->
        :ok

      AccessList.allowed_for_posting?(request[:remote_ip] || request["remote_ip"]) ->
        :ok

      true ->
        {:error, :ipaccess}
    end
  end

  def validate_dnsbl(attrs, request, config) do
    cond do
      not Map.get(config, :use_dnsbl, true) ->
        :ok

      ipaccess_reply_bypass?(attrs, config) ->
        :ok

      ipaccess_bypass?(attrs, config) ->
        :ok

      true ->
        dnsbl_opts =
          case Map.get(request, :dnsbl_resolver) do
            resolver when is_function(resolver, 1) -> [resolver: resolver]
            _ -> []
          end

        case DNSBL.check(Map.get(request, :remote_ip), config, dnsbl_opts) do
          :ok -> :ok
          {:error, _name} -> {:error, :dnsbl}
        end
    end
  end

  def validate_board_lock(config, request, board) do
    if config.board_locked and not moderator_board_access?(request, board) do
      {:error, :board_locked}
    else
      :ok
    end
  end

  def validate_thread_lock(nil, _request, _board), do: :ok

  def validate_thread_lock(%Post{locked: true}, request, board) do
    if moderator_board_access?(request, board), do: :ok, else: {:error, :thread_locked}
  end

  def validate_thread_lock(%Post{}, _request, _board), do: :ok

  def validate_hidden_input(attrs, config, request, board) do
    if moderator_board_access?(request, board) do
      :ok
    else
      hidden_name = to_string(config.hidden_input_name || "hash")

      cond do
        is_nil(config.hidden_input_hash) ->
          :ok

        Map.get(attrs, hidden_name) == config.hidden_input_hash ->
          :ok

        true ->
          {:error, :antispam}
      end
    end
  end

  def validate_antispam_question(false, _attrs, _config, _request, _board), do: :ok

  def validate_antispam_question(true, attrs, config, request, board) do
    if moderator_board_access?(request, board) or not is_binary(config.antispam_question) do
      :ok
    else
      answer =
        attrs["antispam_answer"]
        |> to_string()
        |> String.trim()
        |> String.downcase()

      expected =
        config.antispam_question_answer
        |> to_string()
        |> String.trim()
        |> String.downcase()

      if answer != "" and answer == expected, do: :ok, else: {:error, :antispam}
    end
  end

  def validate_captcha(attrs, config, request, board, op?) do
    if moderator_board_access?(request, board) or not captcha_required?(config, op?) do
      :ok
    else
      Captcha.verify(config, attrs, request)
    end
  end

  def validate_ban(request, board) do
    if moderator_board_access?(request, board) do
      :ok
    else
      if Bans.active_ban_for_request(board, request[:remote_ip] || request["remote_ip"]) do
        {:error, :banned}
      else
        :ok
      end
    end
  end

  def captcha_required?(config, op?) do
    captcha = Map.get(config, :captcha, %{})

    cond do
      not Map.get(captcha, :enabled, false) -> false
      Map.get(captcha, :mode) == "none" -> false
      Map.get(captcha, :mode) == "op" -> op?
      Map.get(captcha, :mode) == "reply" -> not op?
      true -> true
    end
  end

  defp valid_post_button?(value, configured, aliases) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()

    accepted =
      [configured | aliases]
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&(String.trim(&1) |> String.downcase()))

    normalized in accepted
  end

  defp valid_post_button?(_value, _configured, _aliases), do: false

  defp request_moderator(request), do: request[:moderator] || request["moderator"]

  defp ipaccess_bypass?(attrs, config) do
    case Map.get(config, :ip_nulling_flags, 0) do
      threshold when is_integer(threshold) and threshold > 0 ->
        submitted_flag_length(attrs) >= threshold

      _ ->
        false
    end
  end

  defp ipaccess_reply_bypass?(attrs, config) do
    Map.get(config, :ipaccess_replies, false) and reply?(attrs) and not uploaded_file?(attrs)
  end

  defp reply?(attrs) when is_map(attrs), do: present?(Map.get(attrs, "thread"))
  defp reply?(_attrs), do: false

  defp uploaded_file?(attrs) when is_map(attrs) do
    match?(%Plug.Upload{}, Map.get(attrs, "file")) or
      attrs
      |> Map.values()
      |> Enum.any?(fn
        %Plug.Upload{} ->
          true

        uploads when is_list(uploads) ->
          Enum.any?(uploads, &match?(%Plug.Upload{}, &1))

        uploads when is_map(uploads) ->
          uploads |> Map.values() |> Enum.any?(&match?(%Plug.Upload{}, &1))

        _ ->
          false
      end)
  end

  defp uploaded_file?(_attrs), do: false

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(nil), do: false
  defp present?(_value), do: true

  defp submitted_flag_length(attrs) when is_map(attrs) do
    attrs
    |> Map.get("user_flag", Map.get(attrs, "flags", ""))
    |> to_string()
    |> String.trim()
    |> String.length()
  end

  defp submitted_flag_length(_attrs), do: 0

  defp moderator_board_access?(request, board) do
    case request_moderator(request) do
      %ModUser{} = moderator -> Moderation.board_access?(moderator, board)
      _ -> false
    end
  end
end
