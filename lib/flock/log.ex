defmodule Flock.Log do
  @moduledoc "Distributes Flock Log messages to any processes that register as listeners"
  use GenServer
  alias Flock.Topology
  import Flock.Topology, only: [is_node_id: 1]

  def start_link() do
    GenServer.start_link(__MODULE__, :ok, name: Flock.Log)
  end

  @type entry ::
          {:start_node, :requested | :ok | {:error, term()}}
          | {:stop_node, :requested | :ok | {:error, term()}}
          | {:acceptor,
             {:listening, :inet.ip4_address(), integer()}
             | {:waiting_for_port, :inet.ip4_address(), integer()}}
          | {:received, Flock.Protocol.response(), [from: Topology.node_id()]}
          | {:sent, Flock.Protocol.response(),
             [to: Topology.node_id() | list(Topology.node_id())]}
          | :became_leader
          | {:following, Topology.node_id()}
          | {:received_request, [request: Flock.Protocol.request()]}
          | {:handled_request,
             [request: Flock.Protocol.request(), response: Flock.Protocol.response()]}

  @impl GenServer
  def init(:ok) do
    {:ok, []}
  end

  @spec append(Topology.node_id(), entry()) :: :ok
  def append(node_id, entry) when is_node_id(node_id) do
    GenServer.cast(Flock.Log, {:entry, node_id, entry})
  end

  def add_sink(pid) when is_pid(pid) do
    GenServer.cast(Flock.Log, {:add_sink, pid})
  end

  def child_spec(_args) do
    %{
      id: Flock.Log,
      start: {Flock.Log, :start_link, []}
    }
  end

  @impl GenServer
  def handle_cast({:add_sink, pid}, pids) do
    {:noreply, pids ++ [pid]}
  end

  @impl GenServer
  def handle_cast({:entry, node_id, entry}, pids) do
    Enum.each(pids, fn pid ->
      send(pid, {:flock, node_id, entry})
    end)

    {:noreply, pids}
  end
end
