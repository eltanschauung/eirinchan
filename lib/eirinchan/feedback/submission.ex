defmodule Eirinchan.Feedback.Submission do
  @moduledoc "Shared admission for public feedback forms and posting commands."

  alias Eirinchan.{AccessList, Antispam, Feedback, Settings, Tripcode}
  alias Eirinchan.Antispam.PublicActivityPolicy
  alias Eirinchan.Runtime.Config

  @command_limit 2_000

  def command?(body) when is_binary(body), do: Regex.match?(~r/\A\/feedback(?:\s|\z)/u, body)
  def command?(_body), do: false

  def command_attrs(%{"body" => body} = params) when is_binary(body) do
    if command?(body) do
      message = body |> String.replace_prefix("/feedback", "") |> String.trim_leading()

      {:ok,
       %{
         "body" => String.slice(message, 0, @command_limit),
         "name" => Tripcode.display_name(params["name"]),
         "email" => params["email"]
       }}
    else
      :not_command
    end
  end

  def command_attrs(_params), do: :not_command

  def config do
    Settings.current_instance_config()
    |> Config.deep_merge(Application.get_env(:eirinchan, :feedback_overrides, %{}))
    |> then(&Config.compose(nil, &1, %{}))
  end

  def submit(attrs, request, opts \\ []) do
    # Do not use allowed?/1: globally disabled IP enforcement deliberately
    # allows browsing, but it does not establish an authenticated grant.
    if AccessList.allowed_for_posting?(request.remote_ip) do
      submit_authenticated(attrs, request, opts)
    else
      {:ok, nil}
    end
  end

  defp submit_authenticated(attrs, request, opts) do
    config = config()
    # Public callers never control moderation state, IP storage, or admission options.
    attrs = Map.take(attrs, ["name", "email", "body"])

    if Keyword.get(opts, :source, :form) == :form and invalid_form_body?(attrs["body"]) do
      {:error, :body_shape, config.error.antispam}
    else
      case Antispam.reserve_configured_public_activity("feedback", request, config) do
        {:ok, _reservation} ->
          Feedback.create_feedback(attrs, remote_ip: request.remote_ip, config: config)

        {:error, _reason} ->
          {:error, :rate_limited, PublicActivityPolicy.rate_limit_message(:feedback, config)}
      end
    end
  end

  defp invalid_form_body?(body) when is_binary(body), do: not String.contains?(body, " ")
  defp invalid_form_body?(_body), do: false
end
