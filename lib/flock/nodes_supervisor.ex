defmodule Flock.NodesSupervisor do
  @moduledoc "Supervisor that allows clsuter Nodes to be started/stopped"
  use DynamicSupervisor

  alias Flock.NodeSupervisor
  alias Flock.Topology
  import Flock.Topology, only: [is_node_id: 1]

  def start_link() do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__, debug: [])
  end

  @impl DynamicSupervisor
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_node(node_id, topology = %Topology{}) when is_node_id(node_id) do
    child_spec = %{
      id: NodeSupervisor,
      start: {NodeSupervisor, :start_link, [node_id, topology]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  def stop_node(node_id) when is_node_id(node_id) do
    child_pid = NodeSupervisor.node_pid(node_id)
    DynamicSupervisor.terminate_child(__MODULE__, child_pid)
  end
end
