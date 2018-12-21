defmodule Flock.Tcp.Client do
  @moduledoc "Connection to a peer in the cluster via TCP"
  use GenServer

  alias Flock.NodeServer
  alias Flock.Topology
  import Flock.Topology, only: [is_node_id: 1]

  defmodule State do
    @moduledoc false
    use TypedStruct

    typedstruct do
      field(:node_id, String.t(), enforce: true)
      field(:destination_node_id, String.t(), enforce: true)
      field(:topology, map(), enforce: true)
      field(:socket, any())
    end
  end

  #### API ####

  def via_tuple(node_id, destination_node_id)
      when is_node_id(node_id) and is_node_id(destination_node_id)
      when is_binary(node_id) and is_binary(destination_node_id) do
    {:via, Registry, {Flock.Registry, {node_id, __MODULE__, destination_node_id}}}
  end

  def start_link(node_id, destination_node_id, topology = %Topology{})
      when is_node_id(node_id) and is_node_id(destination_node_id) do
    state = %State{node_id: node_id, destination_node_id: destination_node_id, topology: topology}

    GenServer.start_link(
      __MODULE__,
      state,
      name: via_tuple(node_id, destination_node_id),
      debug: []
    )
  end

  @spec send(
          from: Topology.node_id(),
          to: Topology.node_id() | list(Topology.node_id()),
          request: Flock.Protocol.request()
        ) :: :ok
  def send(from: node_id, to: recipients, request: request) when is_node_id(node_id) do
    Flock.Log.append(node_id, {:sent, request, to: recipients})

    recipients
    |> to_list()
    |> Enum.each(fn recipient ->
      packet = Flock.Protocol.encode_request(request)
      GenServer.cast(via_tuple(node_id, recipient), {:send, packet})
    end)

    :ok
  end

  defp to_list(items) when is_list(items), do: items
  defp to_list(item), do: [item]

  #### CALLBACKS ####

  def child_spec([node_id, destination_node_id, topology = %Topology{}])
      when is_node_id(node_id) and is_node_id(destination_node_id) do
    %{
      id: via_tuple(node_id, destination_node_id),
      start: {__MODULE__, :start_link, [node_id, destination_node_id, topology]}
    }
  end

  @impl GenServer
  def init(state = %State{}) do
    send(self(), :after_init)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:after_init, state = %State{}) do
    {:ok, socket} = connect(state)
    {:noreply, %{state | socket: socket}}
  end

  @impl GenServer
  def handle_info({:tcp, _port, packet}, state = %State{}) do
    packet
    |> lines_from_packet()
    |> Enum.each(fn response ->
      handle_response(state.node_id, state.destination_node_id, response)
    end)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:tcp_closed, _port}, state = %State{}) do
    {:ok, socket} = connect(state)
    {:noreply, %{state | socket: socket}}
  end

  @impl GenServer
  def handle_cast({:send, message}, state = %State{}) do
    :ok = :gen_tcp.send(state.socket, "#{message} \n")
    {:noreply, state}
  end

  #### HELPERS ####

  @spec handle_response(Topology.node_id(), Topology.node_id(), String.t()) :: :ok
  defp handle_response(node_id, responder_id, response)
       when is_node_id(node_id) and is_node_id(responder_id) and is_binary(response) do
    decoded = Flock.Protocol.decode_response(response)
    Flock.Log.append(node_id, {:received, decoded, from: responder_id})

    NodeServer.handle_response(node_id, decoded)
  end

  defp lines_from_packet(packet) do
    packet
    |> to_string()
    |> String.split("\n")
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.trim/1)
  end

  defp connect(state = %State{}) do
    {:ok, %{ip: ip, port: port}} = Topology.fetch_node(state.topology, state.destination_node_id)

    case :gen_tcp.connect(ip, port, []) do
      {:ok, socket} ->
        {:ok, socket}

      _ ->
        Process.sleep(2000)
        connect(state)
    end
  end
end
