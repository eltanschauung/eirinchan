defmodule EirinchanWeb.BoardlistPresenter do
  @moduledoc false

  alias EirinchanWeb.Announcements

  def expand_groups(groups, boards, opts \\ []) when is_list(groups) and is_list(boards) do
    board_ids = boards |> Enum.map(&Map.get(&1, :id)) |> Enum.reject(&is_nil/1)
    template_opts = Keyword.put(opts, :board_ids, board_ids)

    Enum.map(groups, fn group ->
      Enum.map(group, &expand_link(&1, template_opts))
    end)
  end

  defp expand_link(%{label: label} = link, opts) when is_binary(label) do
    expanded_label = Announcements.expand_text(label, opts)

    expanded_title =
      case Map.get(link, :title) do
        ^label -> expanded_label
        title when is_binary(title) -> Announcements.expand_text(title, opts)
        title -> title
      end

    link
    |> Map.put(:label, expanded_label)
    |> Map.put(:title, expanded_title)
  end

  defp expand_link(link, _opts), do: link
end
