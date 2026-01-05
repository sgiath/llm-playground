defmodule PlayWeb.ConversationListLive do
  use PlayWeb, :live_view

  alias Play.Conversations

  @impl true
  def mount(_params, _session, socket) do
    profile = socket.assigns.current_scope.profile
    conversations = Conversations.list_conversations(profile)

    socket =
      socket
      |> assign(:conversations, conversations)
      |> assign(:page_title, "Conversations")

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-4xl mx-auto py-8 px-4">
        <div class="flex items-center justify-between mb-8">
          <h1 class="text-3xl font-bold">My Conversations</h1>
          <button phx-click="create_conversation" class="btn btn-primary">
            <.icon name="hero-plus" class="w-5 h-5 mr-1" /> New Conversation
          </button>
        </div>

        <div :if={@conversations == []} class="text-center py-16">
          <.icon
            name="hero-chat-bubble-left-right"
            class="w-16 h-16 mx-auto text-base-content/30 mb-4"
          />
          <h2 class="text-xl font-semibold text-base-content/70 mb-2">No conversations yet</h2>
          <p class="text-base-content/50 mb-6">Create your first conversation to get started.</p>
          <button phx-click="create_conversation" class="btn btn-primary">
            <.icon name="hero-plus" class="w-5 h-5 mr-1" /> Create your first conversation
          </button>
        </div>

        <div :if={@conversations != []} class="grid gap-4">
          <div
            :for={conversation <- @conversations}
            class="card bg-base-200 hover:bg-base-300 transition-colors cursor-pointer"
          >
            <div class="card-body flex-row items-center justify-between">
              <.link navigate={~p"/conv/#{conversation.id}"} class="flex-1 min-w-0">
                <h2 class="card-title text-lg">{conversation.name}</h2>
                <p class="text-sm text-base-content/60">
                  {length(conversation.messages)} messages · Updated {format_datetime(
                    conversation.updated_at
                  )}
                </p>
              </.link>
              <div class="flex items-center gap-2">
                <button
                  phx-click="delete_conversation"
                  phx-value-id={conversation.id}
                  class="btn btn-ghost btn-sm btn-square text-error"
                  data-confirm="Are you sure you want to delete this conversation?"
                >
                  <.icon name="hero-trash" class="w-4 h-4" />
                </button>
                <.link navigate={~p"/conv/#{conversation.id}"}>
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
  def handle_event("create_conversation", _params, socket) do
    profile = socket.assigns.current_scope.profile

    case Conversations.create_conversation(profile, %{name: "New Conversation"}) do
      {:ok, conversation} ->
        {:noreply, push_navigate(socket, to: ~p"/conv/#{conversation.id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create conversation")}
    end
  end

  @impl true
  def handle_event("delete_conversation", %{"id" => conv_id}, socket) do
    profile = socket.assigns.current_scope.profile

    case Conversations.get_conversation(profile, conv_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Conversation not found")}

      conversation ->
        case Conversations.delete_conversation(conversation) do
          {:ok, _} ->
            conversations = Conversations.list_conversations(profile)

            socket =
              socket
              |> assign(:conversations, conversations)
              |> put_flash(:info, "Conversation deleted")

            {:noreply, socket}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete conversation")}
        end
    end
  end

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %H:%M")
  end
end
