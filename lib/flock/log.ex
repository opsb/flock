defmodule Flock.Log do
  @moduledoc "Distributes Flock Log messages to any processes that register as listeners"
  use GenServer
  import Flock.Topology, only: [is_node_id: 1]

  def start_link() do
    GenServer.start_link(__MODULE__, :ok, name: Flock.Log)
  end

  @impl GenServer
  def init(:ok) do
    {:ok, []}
  end

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
