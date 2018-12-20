defmodule Flock.NodeSupervisor do
  @moduledoc "Supervisor for all servers/supervisors required for a particular Node"
  use Supervisor

  alias Flock.NodeServer
  alias Flock.Topology
  alias Flock.Tcp
  import Flock.Topology, only: [is_node_id: 1]

  @node_timeout 300

  def start_link(node_id, topology = %Topology{}) when is_node_id(node_id) do
    Supervisor.start_link(__MODULE__, {node_id, topology}, name: via_tuple(node_id))
  end

  @impl Supervisor
  def init({node_id, topology = %Topology{}}) when is_node_id(node_id) do
    children = [
      %{
        id: Tcp.ServerSupervisor.via_tuple(node_id),
        start: {Tcp.ServerSupervisor, :start_link, [node_id]}
      },
      %{
        id: NodeServer.via_tuple(node_id),
        start: {NodeServer, :start_link, [node_id, topology, &Tcp.Client.send/1, @node_timeout]}
      },
      %{
        id: Tcp.Acceptor.via_tuple(node_id),
        start: {Tcp.Acceptor, :start_link, [node_id, topology]}
      }
    ]

    Supervisor.init(tcp_clients(node_id, topology) ++ children, strategy: :one_for_one)
  end

  def tcp_clients(node_id, topology = %Topology{}) when is_node_id(node_id) do
    Enum.map(Topology.peer_ids(topology, node_id), fn peer_id ->
      {Tcp.Client, [node_id, peer_id, topology]}
    end)
  end

  @spec via_tuple(String.t()) :: {:via, atom(), any()}
  def via_tuple(node_id) do
    {:via, Registry, {Flock.Registry, {node_id, NodeSupervisor}}}
  end

  @spec node_pid(String.t()) :: pid() | nil
  def node_pid(node_id) when is_binary(node_id) do
    GenServer.whereis(via_tuple(node_id))
  end
end
