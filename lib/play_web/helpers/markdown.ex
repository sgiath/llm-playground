defmodule PlayWeb.Helpers.Markdown do
  @moduledoc """
  Helper module for rendering markdown content using MDEx.

  MDEx uses the comrak Rust library via NIF - it's fast and gracefully
  handles incomplete markdown without erroring, making it safe to call
  on every render during streaming.
  """

  @doc """
  Renders markdown content to HTML.

  Returns an empty string for nil or empty content.
  Uses GitHub-flavored markdown extensions and syntax highlighting.
  All links open in a new tab with proper security attributes.
  """
  def render_markdown(nil), do: ""
  def render_markdown(""), do: ""

  def render_markdown(content) do
    content
    |> MDEx.to_html!(
      extension: [table: true, strikethrough: true, autolink: true],
      syntax_highlight: [formatter: {:html_inline, theme: "github_dark"}]
    )
    |> add_link_attributes()
  end

  # Add target="_blank" and rel="noopener noreferrer" to all links
  defp add_link_attributes(html) do
    String.replace(html, ~r/<a href="/, ~S(<a target="_blank" rel="noopener noreferrer" href="))
  end
end
