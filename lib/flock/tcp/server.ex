defmodule Flock.Tcp.Server do
  @moduledoc "Allows peers in the cluster to connect to a Node via TCP"
  use GenServer

  alias Flock.NodeServer
  import Flock.Topology, only: [is_node_id: 1]

  defmodule State do
    @moduledoc false
    defstruct [:node_id]
  end

  def start_link(node_id) when is_node_id(node_id) do
    GenServer.start_link(__MODULE__, %State{node_id: node_id}, debug: [])
  end

  @impl GenServer
  def init(state) do
    {:ok, state}
  end

  @impl GenServer
  def handle_info({:tcp, socket, packet}, state = %State{}) do
    packet
    |> requests_from_packet()
    |> Enum.each(&handle_request(&1, socket, state.node_id))

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:tcp_closed, _socket}, state = %State{}) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:tcp_error, _socket, _reason}, state = %State{}) do
    {:noreply, state}
  end

  defp requests_from_packet(packet) do
    packet
    |> String.split("\n")
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.trim/1)
  end

  defp handle_request(request, socket, node_id) do
    Flock.Log.append(node_id, {:received_request, request: request})

    case NodeServer.handle_request(node_id, request) do
      {:response, response} ->
        Flock.Log.append(node_id, {:handled_request, request: request, response: response})
        :ok = :gen_tcp.send(socket, "#{response}\n")

      :noresponse ->
        Flock.Log.append(node_id, {:handled_request, request: request})
    end

    :ok
  end

  def via_tuple(node_id, socket) when is_node_id(node_id) do
    {:via, Registry, {Flock.Registry, {node_id, __MODULE__, socket}}}
  end
end
