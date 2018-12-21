defmodule Flock.Tcp.Acceptor do
  @moduledoc "Accepts TCP connections from peers and spins up new TCP servers"
  use GenServer
  alias Flock.Tcp.ServerSupervisor
  alias Flock.Topology
  import Flock.Topology, only: [is_node_id: 1]

  @reconnect_period 2000

  defmodule State do
    @moduledoc false
    use TypedStruct

    typedstruct do
      field(:node_id, Topology.node_id(), enforce: true)
      field(:topology, map(), enforce: true)
      field(:acceptor, :inet.socket())
    end
  end

  def start_link(node_id, topology = %Topology{}) when is_node_id(node_id) do
    GenServer.start_link(__MODULE__, %State{
      node_id: node_id,
      topology: topology
    })
  end

  @impl GenServer
  def init(state = %State{}) do
    send(self(), :listen_to_port)
    {:ok, state}
  end

  defp listen_to_port(state = %State{}) do
    {:ok, %{ip: ip, port: port}} = Topology.fetch_node(state.topology, state.node_id)
    gen_tcp_options = [:binary, {:packet, 0}, {:active, true}, {:ip, ip}]

    case :gen_tcp.listen(port, gen_tcp_options) do
      {:ok, acceptor} ->
        Flock.Log.append(state.node_id, {:acceptor, {:listening, ip, port}})
        {:ok, acceptor}

      {:error, error} ->
        Flock.Log.append(state.node_id, {:acceptor, {:waiting_for_port, ip, port}})
        {:error, error}
    end
  end

  defp accept_connection() do
    GenServer.cast(self(), :accept)
  end

  @impl GenServer
  def handle_info(:listen_to_port, state = %State{}) do
    case listen_to_port(state) do
      {:ok, acceptor} ->
        accept_connection()
        {:noreply, %{state | acceptor: acceptor}}

      {:error, error} ->
        Process.send_after(self(), :listen_to_port, @reconnect_period)
        {:noreply, state}
    end
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
  def terminate(_reason, state = %State{acceptor: acceptor}) when not is_nil(acceptor) do
    :gen_tcp.close(state.acceptor)
    :ok
  end

  def terminate(_reason, state = %State{}) do
    :ok
  end

  def via_tuple(node_id) when is_node_id(node_id) do
    {:via, Registry, {Flock.Registry, {node_id, __MODULE__}}}
  end
end
