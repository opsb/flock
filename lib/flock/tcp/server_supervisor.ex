defmodule Flock.Tcp.ServerSupervisor do
  @moduledoc """
  Supervisor for TCP Servers. If a node goes down it's discarded because a new socket will
  need to be requested from the client.
  """
  use DynamicSupervisor
  alias Flock.Tcp.Server
  import Flock.Topology, only: [is_node_id: 1]

  def start_link(node_id) when is_node_id(node_id) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: via_tuple(node_id))
  end

  @impl DynamicSupervisor
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def add_server(node_id, socket) when is_node_id(node_id) do
    child_spec = %{
      id: Server.via_tuple(node_id, socket),
      start: {Server, :start_link, [node_id]},
      restart: :transient
    }

    DynamicSupervisor.start_child(via_tuple(node_id), child_spec)
  end

  def via_tuple(node_id) when is_node_id(node_id) do
    {:via, Registry, {Flock.Registry, {node_id, __MODULE__}}}
  end
end
