defmodule Eirinchan.AprilFoolsTeams do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.AprilFoolsTeam
  alias Eirinchan.Posts.Post
  alias Eirinchan.Posts.PostFile
  alias Eirinchan.Repo

  @max_post_count 9_223_372_036_854_775_807
  @team_6_cutover DateTime.utc_now() |> DateTime.truncate(:second)

  @badge_map %{
    1 => %{label: "Yukari Whale 🐋", html_colour: "#FFBF00"},
    2 => %{label: "Judaism ✡", html_colour: "#000080"},
    3 => %{label: "Otokonoko 🩰", html_colour: "#FF69B4"},
    4 => %{label: "Skuf 🍟", html_colour: "#013220"},
    5 => %{label: "Soyteen 💎", html_colour: "#A0BBC7"},
    6 => %{label: "Nofap 🔞", html_colour: "#abd0f5"},
    7 => %{label: "FUTA 🍆", html_colour: "#9542f5"},
    8 => %{label: "Touhou Project ☯ ⛩️", html_colour: "#E15467"},
    9 => %{label: "Blue Archive ᕕ(◠ڼ◠)ᕗ 😭", html_colour: "#87CEEB"},
    10 => %{label: "Limbus Company ⏰🔥", html_colour: "#d93c27"},
    11 => %{label: "Cobson ♠️", html_colour: "#000000"},
    12 => %{label: "Cobson Haters 🥊", html_colour: "#74eb34"}
  }

  @legacy_team_6_badge %{label: "Finasteride 💊", html_colour: "#ADD8E6"}

  def enabled?(config) when is_map(config), do: Map.get(config, :april_fools_teams, false) == true
  def enabled?(_config), do: false

  def assign_team(attrs, config) when is_map(attrs) and is_map(config) do
    if enabled?(config) do
      case Map.get(attrs, "ip_subnet") do
        ip when is_binary(ip) and ip != "" -> Map.put(attrs, "team", team_for_ip(ip))
        _ -> Map.put(attrs, "team", nil)
      end
    else
      Map.put(attrs, "team", nil)
    end
  end

  def team_for_ip(ip) when is_binary(ip) do
    case :erlang.phash2(ip, 6) + 1 do
      roll when roll in [1, 3, 6] -> 11
      _ -> 12
    end
  end

  def badge(%{team: 6} = post) when is_map(post) do
    if legacy_team_6_post?(post) do
      materialize_badge(@legacy_team_6_badge)
    else
      materialize_badge(Map.get(@badge_map, 6))
    end
  end

  def badge(%{team: team_id}) when is_integer(team_id), do: badge(team_id)

  def badge(team_id) when is_integer(team_id) do
    @badge_map
    |> Map.get(team_id)
    |> materialize_badge()
  end

  def badge(_team_id), do: nil

  def increment_post_count(team_id, repo \\ Repo)

  def increment_post_count(team_id, repo) when is_integer(team_id) do
    increment_post_count(team_id, false, repo)
  end

  def increment_post_count(_team_id, _repo), do: :ok

  def increment_post_count(team_id, _image_post?, repo)
      when is_integer(team_id) do
    increment = Enum.random(1..6)

    case repo.one(from team in AprilFoolsTeam, where: team.team == ^team_id, lock: "FOR UPDATE") do
      %AprilFoolsTeam{} = team ->
        new_count =
          team.post_count
          |> Kernel.+(increment)
          |> min(@max_post_count)

        team
        |> Ecto.Changeset.change(post_count: new_count)
        |> repo.update!()

        :ok

      _ ->
        :ok
    end
  end

  def increment_post_count(_team_id, _image_post?, _repo), do: :ok

  def team_tuple(team_id, repo \\ Repo) when is_integer(team_id) do
    case repo.get(AprilFoolsTeam, team_id) do
      %AprilFoolsTeam{} = team ->
        {team.team, team.display_name, team.html_colour, team.post_count}

      _ ->
        nil
    end
  end

  def dynamic_team_variable(name, repo \\ Repo)

  def dynamic_team_variable("team_" <> suffix, repo) do
    case Integer.parse(String.trim(suffix)) do
      {team_id, ""} -> team_tuple(team_id, repo)
      _ -> nil
    end
  end

  def dynamic_team_variable(_name, _repo), do: nil

  def silly_post_count(post_count) when is_integer(post_count) and post_count >= 0 do
    replacement = replacement_for_two(post_count)

    post_count
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.map_join(&replace_post_count_grapheme(&1, replacement))
  end

  def silly_post_count(post_count) when is_binary(post_count) do
    case Integer.parse(post_count) do
      {parsed, ""} -> silly_post_count(parsed)
      _ -> "0"
    end
  end

  def silly_post_count(_post_count), do: "0"

  def image_post?(%Post{} = post) do
    image_file?(post) or
      post
      |> Map.get(:extra_files, [])
      |> Enum.any?(&image_file?/1)
  end

  def image_post?(_post), do: false

  defp contrast_text_colour("#" <> hex) when byte_size(hex) == 6 do
    <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>> = hex

    brightness =
      trunc(String.to_integer(r, 16) * 0.299 + String.to_integer(g, 16) * 0.587 + String.to_integer(b, 16) * 0.114)

    if brightness >= 186, do: "#000000", else: "#ffffff"
  rescue
    _ -> "#000000"
  end

  defp contrast_text_colour(_html_colour), do: "#000000"

  defp replace_post_count_grapheme("1", _replacement), do: "1488"
  defp replace_post_count_grapheme("2", replacement), do: replacement
  defp replace_post_count_grapheme("3", _replacement), do: "33"
  defp replace_post_count_grapheme("6", _replacement), do: "Ϫ"
  defp replace_post_count_grapheme("7", _replacement), do: "Ϫ"
  defp replace_post_count_grapheme("8", _replacement), do: "∞"
  defp replace_post_count_grapheme("9", _replacement), do: "⑨"
  defp replace_post_count_grapheme(grapheme, _replacement), do: grapheme

  defp replacement_for_two(post_count) when is_integer(post_count) do
    case :erlang.phash2(post_count, 4) + 1 do
      1 -> "'son"
      2 -> "clitty"
      3 -> "bald"
      4 -> "whale"
    end
  end

  defp legacy_team_6_post?(%{inserted_at: %NaiveDateTime{} = inserted_at}) do
    inserted_at
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.compare(@team_6_cutover) == :lt
  end

  defp legacy_team_6_post?(%{inserted_at: %DateTime{} = inserted_at}) do
    DateTime.compare(inserted_at, @team_6_cutover) == :lt
  end

  defp legacy_team_6_post?(_post), do: false

  defp materialize_badge(%{label: label, html_colour: html_colour}) do
    %{
      label: label,
      html_colour: html_colour,
      text_colour: contrast_text_colour(html_colour)
    }
  end

  defp materialize_badge(_badge), do: nil

  defp image_file?(%Post{file_type: file_type}), do: image_file_type?(file_type)
  defp image_file?(%PostFile{file_type: file_type}), do: image_file_type?(file_type)
  defp image_file?(%{file_type: file_type}), do: image_file_type?(file_type)
  defp image_file?(_file), do: false

  defp image_file_type?(<<"image/", _::binary>>), do: true
  defp image_file_type?(_file_type), do: false
end
