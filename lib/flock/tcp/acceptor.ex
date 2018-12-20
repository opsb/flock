defmodule Flock.Tcp.Acceptor do
  @moduledoc "Accepts TCP connections from peers and spins up new TCP servers"
  use GenServer
  alias Flock.Tcp.ServerSupervisor
  alias Flock.Topology
  import Flock.Topology, only: [is_node_id: 1]

  defmodule State do
    @moduledoc false
    use TypedStruct

    typedstruct do
      field(:node_id, String.t())
      field(:topology, map())
      field(:acceptor, :inet.socket())
    end
  end

  def start_link(node_id, topology = %Topology{}) when is_node_id(node_id) do
    {:ok, %{ip: ip, port: port}} = Topology.fetch_node(topology, node_id)
    gen_tcp_options = [:binary, {:packet, 0}, {:active, true}, {:ip, ip}]

    case :gen_tcp.listen(port, gen_tcp_options) do
      {:ok, acceptor} ->
        {:ok, pid} =
          GenServer.start_link(__MODULE__, %State{
            node_id: node_id,
            topology: topology,
            acceptor: acceptor
          })

        {:ok, _port} = :inet.port(acceptor)
        {:ok, pid}

      _ ->
        {:error, {:port_not_available, port}}
    end
  end

  @impl GenServer
  def init(state = %State{}) do
    accept_connection()
    {:ok, state}
  end

  defp accept_connection() do
    GenServer.cast(self(), :accept)
  end

  @impl GenServer
  def handle_cast(:accept, state = %State{}) do
    {:ok, client_socket} = :gen_tcp.accept(state.acceptor)
    {:ok, client_server} = ServerSupervisor.add_server(state.node_id, client_socket)

    :ok = :gen_tcp.controlling_process(client_socket, client_server)
    accept_connection()
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state = %State{}) do
    :gen_tcp.close(state.acceptor)
    :ok
  end

  def via_tuple(node_id) when is_node_id(node_id) do
    {:via, Registry, {Flock.Registry, {node_id, __MODULE__}}}
  end
end
