defmodule PlayWeb.AgentListLive do
  use PlayWeb, :live_view

  alias Play.Agents

  @impl true
  def mount(_params, _session, socket) do
    profile = socket.assigns.current_scope.profile
    agents = Agents.list_agents(profile)

    socket =
      socket
      |> assign(:agents, agents)
      |> assign(:page_title, "Agents")

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-4xl mx-auto py-8 px-4">
        <div class="flex items-center justify-between mb-8">
          <h1 class="text-3xl font-bold">My Agents</h1>
          <button phx-click="create_agent" class="btn btn-primary">
            <.icon name="hero-plus" class="w-5 h-5 mr-1" /> New Agent
          </button>
        </div>

        <div :if={@agents == []} class="text-center py-16">
          <.icon name="hero-rectangle-group" class="w-16 h-16 mx-auto text-base-content/30 mb-4" />
          <h2 class="text-xl font-semibold text-base-content/70 mb-2">No agents yet</h2>
          <p class="text-base-content/50 mb-6">Create your first workflow agent to get started.</p>
          <button phx-click="create_agent" class="btn btn-primary">
            <.icon name="hero-plus" class="w-5 h-5 mr-1" /> Create your first agent
          </button>
        </div>

        <div :if={@agents != []} class="grid gap-4">
          <div
            :for={agent <- @agents}
            class="card bg-base-200 hover:bg-base-300 transition-colors cursor-pointer"
          >
            <div class="card-body flex-row items-center justify-between">
              <.link navigate={~p"/agent/#{agent.id}"} class="flex-1 min-w-0">
                <h2 class="card-title text-lg">{agent.name}</h2>
                <p class="text-sm text-base-content/60">
                  Updated {format_datetime(agent.updated_at)}
                </p>
              </.link>
              <div class="flex items-center gap-2">
                <button
                  phx-click="delete_agent"
                  phx-value-id={agent.id}
                  class="btn btn-ghost btn-sm btn-square text-error"
                  data-confirm="Are you sure you want to delete this agent?"
                >
                  <.icon name="hero-trash" class="w-4 h-4" />
                </button>
                <.link navigate={~p"/agent/#{agent.id}"}>
                  <.icon name="hero-chevron-right" class="w-5 h-5 text-base-content/40" />
                </.link>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("create_agent", _params, socket) do
    profile = socket.assigns.current_scope.profile

    case Agents.create_agent(profile, %{name: "Untitled Agent"}) do
      {:ok, agent} ->
        {:noreply, push_navigate(socket, to: ~p"/agent/#{agent.id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create agent")}
    end
  end

  @impl true
  def handle_event("delete_agent", %{"id" => agent_id}, socket) do
    profile = socket.assigns.current_scope.profile

    case Agents.get_agent(profile, agent_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Agent not found")}

      agent ->
        case Agents.delete_agent(agent) do
          {:ok, _} ->
            agents = Agents.list_agents(profile)

            socket =
              socket
              |> assign(:agents, agents)
              |> put_flash(:info, "Agent deleted")

            {:noreply, socket}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete agent")}
        end
    end
  end

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %H:%M")
  end
end
