defmodule Play.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PlayWeb.Telemetry,
      Play.Repo,
      {DNSCluster, query: Application.get_env(:play, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Play.PubSub},
      SgiathAuth.Supervisor,
      PlayWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Play.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    PlayWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
