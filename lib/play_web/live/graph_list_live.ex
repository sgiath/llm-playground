defmodule PlayWeb.GraphListLive do
  use PlayWeb, :live_view

  alias Play.Graphs

  @impl true
  def mount(_params, _session, socket) do
    profile = socket.assigns.current_scope.profile
    graphs = Graphs.list_graphs(profile)

    socket =
      socket
      |> assign(:graphs, graphs)
      |> assign(:page_title, "Graphs")

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-4xl mx-auto py-8 px-4">
        <div class="flex items-center justify-between mb-8">
          <h1 class="text-3xl font-bold">My Graphs</h1>
          <button phx-click="create_graph" class="btn btn-primary">
            <.icon name="hero-plus" class="w-5 h-5 mr-1" /> New Graph
          </button>
        </div>

        <div :if={@graphs == []} class="text-center py-16">
          <.icon name="hero-rectangle-group" class="w-16 h-16 mx-auto text-base-content/30 mb-4" />
          <h2 class="text-xl font-semibold text-base-content/70 mb-2">No graphs yet</h2>
          <p class="text-base-content/50 mb-6">Create your first workflow graph to get started.</p>
          <button phx-click="create_graph" class="btn btn-primary">
            <.icon name="hero-plus" class="w-5 h-5 mr-1" /> Create your first graph
          </button>
        </div>

        <div :if={@graphs != []} class="grid gap-4">
          <.link
            :for={graph <- @graphs}
            navigate={~p"/graph/#{graph.id}"}
            class="card bg-base-200 hover:bg-base-300 transition-colors cursor-pointer"
          >
            <div class="card-body flex-row items-center justify-between">
              <div>
                <h2 class="card-title text-lg">{graph.name}</h2>
                <p class="text-sm text-base-content/60">
                  Updated {format_datetime(graph.updated_at)}
                </p>
              </div>
              <div class="flex items-center gap-2">
                <button
                  phx-click="delete_graph"
                  phx-value-id={graph.id}
                  class="btn btn-ghost btn-sm btn-square text-error"
                  data-confirm="Are you sure you want to delete this graph?"
                >
                  <.icon name="hero-trash" class="w-4 h-4" />
                </button>
                <.icon name="hero-chevron-right" class="w-5 h-5 text-base-content/40" />
              </div>
            </div>
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("create_graph", _params, socket) do
    profile = socket.assigns.current_scope.profile

    case Graphs.create_graph(profile, %{name: "Untitled Graph"}) do
      {:ok, graph} ->
        {:noreply, push_navigate(socket, to: ~p"/graph/#{graph.id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create graph")}
    end
  end

  @impl true
  def handle_event("delete_graph", %{"id" => graph_id}, socket) do
    profile = socket.assigns.current_scope.profile

    case Graphs.get_graph(profile, graph_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Graph not found")}

      graph ->
        case Graphs.delete_graph(graph) do
          {:ok, _} ->
            graphs = Graphs.list_graphs(profile)

            socket =
              socket
              |> assign(:graphs, graphs)
              |> put_flash(:info, "Graph deleted")

            {:noreply, socket}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete graph")}
        end
    end
  end

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %H:%M")
  end
end
