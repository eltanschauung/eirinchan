defmodule Eirinchan.ThemeRegistry do
  @moduledoc false

  @title %{name: "title", title: "Title", type: "text", default: "", max: 200}
  @subtitle %{
    name: "subtitle",
    title: "Subtitle",
    type: "text",
    default: "",
    max: 500,
    comment: "Optional."
  }
  @exclude %{
    name: "exclude",
    title: "Excluded boards",
    type: "text",
    default: "",
    max: 1_000,
    comment: "Space-separated board URIs."
  }

  @themes [
    %{
      name: "categories",
      title: "Categories",
      description: "Category-grouped landing page with a removable, responsive sidebar.",
      version: "0.3-elixir",
      page_theme: true,
      default_installed: false,
      public_path: "/categories",
      config_fields: [
        %{@title | title: "Site title", default: "Eirinchan Categories"},
        @subtitle,
        %{
          name: "category_titles",
          title: "Category titles",
          type: "text",
          default: "",
          max: 1_000,
          comment: "Optional pipe-separated titles matching the configured boardlist groups."
        }
      ]
    },
    %{
      name: "faq",
      title: "FAQ",
      description: "Manage the public FAQ page.",
      version: "1.1-elixir",
      page_theme: false,
      default_installed: false,
      public_path: "/faq",
      config_fields: [
        %{
          name: "html",
          title: "HTML",
          type: "textarea",
          default: "",
          max: 100_000,
          trim: false,
          rows: 30,
          comment: "Sanitized before it is shown publicly."
        }
      ]
    },
    %{
      name: "feedback",
      title: "Feedback",
      description: "Public feedback page and submission form.",
      version: "1.1-elixir",
      page_theme: false,
      default_installed: false,
      public_path: "/feedback",
      config_fields: [%{@title | default: "Feedback"}]
    },
    %{
      name: "frameset",
      title: "Frameset",
      description: "Classic board-and-news landing page using same-origin responsive frames.",
      version: "0.1-elixir",
      page_theme: true,
      default_installed: false,
      public_path: "/frameset",
      config_fields: [
        %{@title | title: "Site title", default: "Eirinchan Frameset"},
        @subtitle
      ]
    },
    %{
      name: "index",
      title: "Index",
      description:
        "Rich landing page with boards, news, featured media, recent posts, and stats.",
      version: "1.0-elixir",
      page_theme: true,
      default_installed: false,
      public_path: "/index",
      config_fields: [
        %{
          name: "icon",
          title: "Icon URL",
          type: "text",
          default: "/site_logo.png",
          max: 2_048,
          format: :https_or_local_url
        },
        %{@title | default: "Welcome to Eirinchan"},
        %{@subtitle | default: "What is chaos for the fly is normal for the spider."},
        %{
          name: "description",
          title: "Description",
          type: "textarea",
          default: "Short description for your website.",
          max: 20_000,
          trim: false,
          rows: 8,
          comment: "Sanitized before it is shown publicly."
        },
        %{
          name: "imageofnow",
          title: "Image of the now URL",
          type: "text",
          default: "",
          max: 2_048,
          format: :https_or_local_url
        },
        %{
          name: "quoteofnow",
          title: "Quote of the now",
          type: "textarea",
          default: "",
          max: 20_000,
          trim: false,
          rows: 6,
          comment: "Sanitized before it is shown publicly."
        },
        %{
          name: "videoofnow",
          title: "YouTube video URL",
          type: "text",
          default: "",
          max: 2_048,
          format: :youtube_url,
          comment: "YouTube watch, youtu.be, or embed URLs only."
        },
        %{
          name: "no_recent",
          title: "Recent news entries",
          type: "number",
          default: "5",
          min: 0,
          max: 100,
          comment: "0 shows all configured news entries."
        },
        @exclude,
        %{
          name: "excludeboardlist",
          title: "Boards hidden from the board list",
          type: "text",
          default: "",
          max: 1_000,
          comment: "Space-separated board URIs."
        },
        %{
          name: "limit_images",
          title: "Recent images",
          type: "number",
          default: "15",
          min: 0,
          max: 100
        },
        %{
          name: "limit_posts",
          title: "Recent posts",
          type: "number",
          default: "30",
          min: 0,
          max: 100
        }
      ]
    },
    %{
      name: "recent",
      title: "RecentPosts",
      description: "Primary landing page with editable content, recent posts, images, and stats.",
      version: "1.1-elixir",
      page_theme: true,
      default_installed: true,
      public_path: "/recent",
      config_fields: [
        %{@title | default: "Recent Posts"},
        %{
          name: "body",
          title: "Homepage HTML",
          type: "textarea",
          default: "",
          max: 100_000,
          trim: false,
          rows: 30,
          comment: "Sanitized before it is shown above the live recent-post panels."
        },
        @exclude,
        %{
          name: "limit_images",
          title: "Recent images",
          type: "number",
          default: "3",
          min: 0,
          max: 100
        },
        %{
          name: "limit_posts",
          title: "Recent posts",
          type: "number",
          default: "30",
          min: 0,
          max: 100
        }
      ]
    },
    %{
      name: "rss",
      title: "RSS",
      description: "RSS 2.0 feed of recent posts, served dynamically at /recent.xml.",
      version: "0.1-elixir",
      page_theme: true,
      default_installed: false,
      public_path: "/recent.xml",
      config_fields: [
        %{@title | default: "Recent Posts RSS"},
        %{@subtitle | title: "Feed description", default: "Recent posts"},
        @exclude,
        %{
          name: "limit_posts",
          title: "Recent posts",
          type: "number",
          default: "30",
          min: 0,
          max: 100
        }
      ]
    },
    %{
      name: "sitemap",
      title: "Sitemap",
      description: "Standards-compliant XML sitemap served dynamically at /sitemap.xml.",
      version: "1.1-elixir",
      page_theme: true,
      default_installed: true,
      public_path: "/sitemap.xml",
      config_fields: [
        %{
          name: "changefreq",
          title: "Thread change frequency",
          type: "select",
          default: "hourly",
          options: ~w(always hourly daily weekly monthly yearly never)
        },
        %{
          name: "boards",
          title: "Included boards",
          type: "text",
          default: "*",
          max: 1_000,
          comment: "* includes every board; otherwise use space-separated board URIs."
        }
      ]
    },
    %{
      name: "ukko",
      title: "Overboard (Ukko)",
      description: "Paginated board containing recently bumped threads from selected boards.",
      version: "0.3-elixir",
      page_theme: true,
      default_installed: true,
      public_path: :configured,
      config_fields: [
        %{@title | title: "Board name", default: "Ukko"},
        %{
          name: "uri",
          title: "Board URI",
          type: "text",
          default: "ukko",
          max: 32,
          format: :route_segment,
          comment: "Lowercase letters, numbers, underscores, and hyphens."
        },
        %{@subtitle | comment: "%s is replaced with the configured thread limit."},
        @exclude,
        %{
          name: "thread_limit",
          title: "Threads per page",
          type: "number",
          default: "15",
          min: 1,
          max: 100
        }
      ]
    }
  ]

  @reserved_route_segments ~w(
    api auth banners catalog categories csrf-token faq feedback flag flags formatting frameset
    index manage mod.php news pages post.php recent recent.xml rules search setup sitemap.xml
    theme watcher
  )

  def all, do: @themes

  def get(name) when is_binary(name) do
    normalized = String.trim(name)
    Enum.find(@themes, &(&1.name == normalized))
  end

  def get(_name), do: nil

  def default_settings(theme), do: normalize_settings(theme, %{})

  def normalize_settings(theme, params) when is_map(theme) and is_map(params) do
    Map.new(theme.config_fields, fn field ->
      raw = fetch_param(params, field.name, field.default)
      {field.name, normalize_value(field, raw)}
    end)
  end

  def normalize_settings(_theme, _params), do: %{}

  def validate_settings(theme, settings) when is_map(theme) and is_map(settings) do
    errors =
      theme.config_fields
      |> Enum.flat_map(&validate_field(&1, Map.get(settings, &1.name, &1.default)))

    case errors do
      [] -> :ok
      _ -> {:error, errors}
    end
  end

  def youtube_embed_url(value) when is_binary(value) do
    case youtube_video_id(value) do
      nil -> nil
      video_id -> "https://www.youtube-nocookie.com/embed/#{video_id}"
    end
  end

  def youtube_embed_url(_value), do: nil

  def media_url(value) when is_binary(value) do
    if value == "" or safe_media_url?(value), do: value, else: ""
  end

  def media_url(_value), do: ""

  def safe_route_segment?(value) when is_binary(value) do
    String.match?(value, ~r/^[a-z0-9][a-z0-9_-]{0,31}$/) and
      value not in @reserved_route_segments
  end

  def safe_route_segment?(_value), do: false

  defp fetch_param(params, key, default) do
    atom_key = String.to_existing_atom(key)
    Map.get(params, key, Map.get(params, atom_key, default))
  rescue
    ArgumentError -> Map.get(params, key, default)
  end

  defp normalize_value(%{type: "checkbox"}, raw), do: raw in [true, "true", "1", 1, "on"]

  defp normalize_value(field, raw) do
    value = to_string(raw || "")
    value = if Map.get(field, :trim, true), do: String.trim(value), else: value

    case Map.get(field, :format) do
      :youtube_url -> youtube_embed_url(value) || value
      _ -> value
    end
  end

  defp validate_field(%{type: "number"} = field, value) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} when parsed >= field.min and parsed <= field.max -> []
      _ -> ["#{field.title} must be an integer from #{field.min} to #{field.max}."]
    end
  end

  defp validate_field(%{type: "select"} = field, value) do
    if to_string(value) in field.options, do: [], else: ["#{field.title} is invalid."]
  end

  defp validate_field(field, value) do
    string = to_string(value)

    []
    |> validate_max_length(field, string)
    |> validate_format(field, string)
  end

  defp validate_max_length(errors, %{max: max, title: title}, value)
       when is_integer(max) do
    if String.length(value) <= max, do: errors, else: ["#{title} is too long." | errors]
  end

  defp validate_max_length(errors, _field, _value), do: errors

  defp validate_format(errors, %{format: :https_or_local_url, title: title}, value) do
    if value == "" or safe_media_url?(value),
      do: errors,
      else: ["#{title} must be a local path or HTTPS URL." | errors]
  end

  defp validate_format(errors, %{format: :youtube_url, title: title}, value) do
    if value == "" or youtube_video_id(value),
      do: errors,
      else: ["#{title} must be a YouTube URL." | errors]
  end

  defp validate_format(errors, %{format: :route_segment, title: title}, value) do
    if safe_route_segment?(value),
      do: errors,
      else: ["#{title} is invalid or conflicts with a built-in route." | errors]
  end

  defp validate_format(errors, _field, _value), do: errors

  defp safe_media_url?("/" <> rest) do
    rest != "" and not String.starts_with?(rest, "/") and not unsafe_url_text?(rest)
  end

  defp safe_media_url?(value) do
    uri = URI.parse(value)

    uri.scheme == "https" and is_binary(uri.host) and uri.host != "" and is_nil(uri.userinfo) and
      not unsafe_url_text?(value)
  end

  defp unsafe_url_text?(value) do
    String.contains?(value, ["\\", "\r", "\n", "\0"])
  end

  defp youtube_video_id(value) do
    uri = URI.parse(value)
    host = uri.host && String.downcase(uri.host)

    candidate =
      cond do
        host in ["youtu.be", "www.youtu.be"] ->
          uri.path
          |> to_string()
          |> String.trim("/")
          |> String.split("/", parts: 2)
          |> List.first()

        host in ["youtube.com", "www.youtube.com", "m.youtube.com"] and uri.path == "/watch" ->
          uri.query |> to_string() |> URI.decode_query() |> Map.get("v")

        host in ["youtube.com", "www.youtube.com", "www.youtube-nocookie.com"] and
            String.starts_with?(uri.path || "", "/embed/") ->
          uri.path
          |> String.trim_leading("/embed/")
          |> String.split("/", parts: 2)
          |> List.first()

        true ->
          nil
      end

    if is_binary(candidate) and String.match?(candidate, ~r/^[A-Za-z0-9_-]{10,11}$/),
      do: candidate
  rescue
    _ -> nil
  end
end
