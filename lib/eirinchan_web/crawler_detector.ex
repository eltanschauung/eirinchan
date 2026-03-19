defmodule EirinchanWeb.CrawlerDetector do
  @moduledoc false

  @crawler_patterns [
    ~r/\bgooglebot\b/i,
    ~r/\bbingbot\b/i,
    ~r/\bslurp\b/i,
    ~r/\bduckduckbot\b/i,
    ~r/\bbaiduspider\b/i,
    ~r/\byandex(bot|images)?\b/i,
    ~r/\bfacebot\b/i,
    ~r/\bfacebookexternalhit\b/i,
    ~r/\bapplebot\b/i,
    ~r/\bpetalbot\b/i,
    ~r/\bsemrushbot\b/i,
    ~r/\bahrefsbot\b/i,
    ~r/\bmj12bot\b/i,
    ~r/\bdotbot\b/i,
    ~r/\bseekport\b/i,
    ~r/\bsogou\b/i,
    ~r/\bpython-requests\b/i,
    ~r/\bcurl\b/i,
    ~r/\bwget\b/i,
    ~r/\bgo-http-client\b/i,
    ~r/\bheadlesschrome\b/i,
    ~r/\bphantomjs\b/i,
    ~r/\bselenium\b/i,
    ~r/\bspider\b/i,
    ~r/\bcrawler\b/i,
    ~r/\bbot\b/i
  ]

  def crawler?(user_agent) when is_binary(user_agent) do
    trimmed = String.trim(user_agent)

    trimmed != "" and Enum.any?(@crawler_patterns, &Regex.match?(&1, trimmed))
  end

  def crawler?(_), do: false
end
