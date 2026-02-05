defmodule PlayWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use PlayWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8 bg-base-200">
      <div class="flex-1">
        <a href="/" class="btn btn-ghost text-xl font-bold">
          Playground
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-row px-1 space-x-2 items-center">
          <li>
            <a href="/agent" class="btn btn-ghost">Agents</a>
          </li>
          <li>
            <a href="/conv" class="btn btn-ghost">Conversations</a>
          </li>
          <%= if @current_scope && @current_scope.user do %>
            <li>
              <.profile_menu current_scope={@current_scope} />
            </li>
          <% else %>
            <li>
              <a href="/sign-in" class="btn btn-ghost">Sign In</a>
            </li>
            <li>
              <a href="/sign-up" class="btn btn-primary">Sign Up</a>
            </li>
          <% end %>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto w-full space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  attr :current_scope, :map, required: true

  defp profile_menu(assigns) do
    ~H"""
    <details class="dropdown dropdown-end">
      <summary class="btn btn-ghost btn-circle">
        <.icon name="hero-user-circle" class="size-7" />
      </summary>
      <ul class="dropdown-content menu bg-base-100 rounded-box z-10 w-52 p-2 shadow-lg border border-base-300">
        <li class="menu-title">
          <span class="text-xs truncate">{@current_scope.user["email"]}</span>
        </li>
        <li>
          <a href="/sign-out" class="text-error">
            <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" /> Sign Out
          </a>
        </li>
      </ul>
    </details>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
