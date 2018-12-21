defmodule Flock.NodeServer do
  @moduledoc "Represents a Node in the cluster"
  use GenServer
  use TypedStruct

  alias Flock.Topology
  import Flock.Topology, only: [is_node_id: 1]

  @type status ::
          :noleader
          | :checking_candidates
          | {:following, String.t()}
          | :leading
          | :waiting_for_new_leader
          | {:pinging, String.t()}

  defmodule State do
    @moduledoc false
    typedstruct do
      field(:node_id, String.t())
      field(:status, Flock.NodeServer.status(), default: :noleader)
      field(:topology, Topology.t())
      field(:leader_waiters, list(), default: [])
      field(:send_request, any())
      field(:timeout, integer())
    end

    def fetch_leader(%State{status: {:following, leader_id}}), do: {:ok, leader_id}
    def fetch_leader(%State{status: {:pinging, leader_id}}), do: {:ok, leader_id}
    def fetch_leader(%State{status: :leading, node_id: node_id}), do: {:ok, node_id}
    def fetch_leader(_), do: :none

    def update_status(state = %State{}, new_status) do
      %{state | status: new_status}
    end

    def add_leader_waiter(state = %State{}, from) do
      %{state | leader_waiters: state.leader_waiters ++ [from]}
    end

    def pop_leader_waiters(state = %State{}) do
      {%{state | leader_waiters: []}, state.leader_waiters}
    end
  end

  #### API ####

  def start_link(node_id, topology = %Topology{}, send_request, timeout)
      when is_node_id(node_id) do
    state = %State{
      node_id: node_id,
      status: :noleader,
      topology: topology,
      send_request: send_request,
      timeout: timeout
    }

    GenServer.start_link(__MODULE__, state, name: via_tuple(node_id), debug: [])
  end

  @spec handle_response(Topology.node_id(), Flock.Protocol.response()) :: :ok
  def handle_response(node_id, response) when is_node_id(node_id) do
    GenServer.call(via_tuple(node_id), {:response, response})
  end

  @spec handle_request(Topology.node_id(), Flock.Protocol.request()) ::
          {:response, Flock.Protocol.response()} | :noresponse
  def handle_request(node_id, request) when is_node_id(node_id) do
    GenServer.call(via_tuple(node_id), {:request, request})
  end

  @spec leader(Topology.node_id()) :: Topology.node_id()
  def leader(node_id) when is_node_id(node_id) do
    GenServer.call(via_tuple(node_id), :leading, 10_000)
  end

  def via_tuple(node_id) when is_node_id(node_id) do
    {:via, Registry, {Flock.Registry, {node_id, NodeServer}}}
  end

  #### CALLBACKS ####

  @impl GenServer
  def init(state) do
    send(self(), :after_init)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:after_init, state = %State{}) do
    {:noreply, begin_election(state)}
  end

  def handle_info(:wait_for_leader_over, state = %State{status: :waiting_for_new_leader}) do
    {:noreply, begin_election(state)}
  end

  def handle_info(:wait_for_leader_over, state = %State{}) do
    {:noreply, state}
  end

  def handle_info(:candidates_collected, state = %State{status: :checking_candidates}) do
    {:noreply, become_leader(state)}
  end

  def handle_info(:candidates_collected, state = %State{}) do
    {:noreply, state}
  end

  def handle_info(:ping_triggered, state = %State{status: {:following, leader_id}}) do
    {:noreply, ping_leader(state, leader_id)}
  end

  def handle_info(:ping_triggered, state = %State{}) do
    {:noreply, state}
  end

  def handle_info(:ping_timeout, state = %State{status: {:pinging, _leader}}) do
    {:noreply, begin_election(state)}
  end

  def handle_info(:ping_timeout, state = %State{}) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:request, :alive?}, _from, state = %State{}) do
    {:reply, {:response, :finethanks}, begin_election(state)}
  end

  @impl GenServer
  def handle_call({:request, :ping}, _from, state = %State{}) do
    {:reply, {:response, :pong}, state}
  end

  @impl GenServer
  def handle_call({:request, {:iamtheking, leader_id}}, _from, state = %State{})
      when is_node_id(leader_id) do
    {:reply, :noresponse, follow_leader(state, leader_id)}
  end

  @impl GenServer
  def handle_call({:response, :finethanks}, _from, state = %State{status: :checking_candidates}) do
    {:reply, :ok, wait_for_leader(state)}
  end

  @impl GenServer
  def handle_call({:response, :finethanks}, _from, state = %State{}) do
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:response, :pong}, _from, state = %State{status: {:pinging, leader_id}}) do
    {:reply, :ok, schedule_ping(state, leader_id)}
  end

  @impl GenServer
  def handle_call({:response, :pong}, _from, state = %State{}) do
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:leading, from, state = %State{}) do
    case State.fetch_leader(state) do
      :none ->
        {:noreply, state |> State.add_leader_waiter(from)}

      {:ok, leader_id} ->
        {:reply, leader_id, state}
    end
  end

  #### HELPERS ####

  defp send_request(state = %State{}, args) do
    state.send_request.(args)
  end

  defp begin_election(state = %State{}) do
    candidate_ids = Topology.candidate_ids(state.topology, state.node_id)

    if Enum.empty?(candidate_ids) do
      become_leader(state)
    else
      ask_candidates(state, candidate_ids)
    end
  end

  #### TRANSITIONS ####

  defp ask_candidates(state = %State{}, candidate_ids) when is_list(candidate_ids) do
    send_request(
      state,
      from: state.node_id,
      to: Topology.candidate_ids(state.topology, state.node_id),
      request: :alive?
    )

    Process.send_after(self(), :candidates_collected, state.timeout)

    State.update_status(state, :checking_candidates)
  end

  defp wait_for_leader(state = %State{}) do
    Process.send_after(self(), :wait_for_leader_over, state.timeout)
    State.update_status(state, :waiting_for_new_leader)
  end

  defp become_leader(state = %State{}) do
    if state.status != :leading do
      Flock.Log.append(state.node_id, :became_leader)
    end

    send_request(
      state,
      from: state.node_id,
      to: Topology.peer_ids(state.topology, state.node_id),
      request: {:iamtheking, state.node_id}
    )

    state
    |> State.update_status(:leading)
    |> notify_leader_waiters()
  end

  defp follow_leader(state = %State{}, leader_id) when is_node_id(leader_id) do
    Flock.Log.append(state.node_id, {:following, leader_id})

    state
    |> schedule_ping(leader_id)
    |> notify_leader_waiters()
  end

  def schedule_ping(state = %State{}, leader_id) when is_node_id(leader_id) do
    Process.send_after(self(), :ping_triggered, state.timeout)

    state
    |> State.update_status({:following, leader_id})
  end

  defp ping_leader(state = %State{}, leader_id) when is_node_id(leader_id) do
    send_request(state, from: state.node_id, to: leader_id, request: :ping)
    Process.send_after(self(), :ping_timeout, 4 * state.timeout)
    State.update_status(state, {:pinging, leader_id})
  end

  defp notify_leader_waiters(state = %State{}) do
    {updated_state, waiters} = State.pop_leader_waiters(state)
    {:ok, leader} = State.fetch_leader(updated_state)

    Enum.each(waiters, fn from ->
      GenServer.reply(from, leader)
    end)

    updated_state
  end
end
