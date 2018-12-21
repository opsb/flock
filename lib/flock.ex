defmodule Flock do
  @moduledoc "The Flock application, starts all services required to run Flock Nodes"
  use Application
  use TypedStruct

  alias Flock.NodesSupervisor
  alias Flock.NodeServer
  alias Flock.Topology
  import Flock.Topology, only: [is_node_id: 1]

  def start(_start_type, _start_args) do
    import Supervisor.Spec

    children = [
      Flock.Log,
      {Registry, keys: :unique, name: Flock.Registry},
      supervisor(Flock.NodesSupervisor, [])
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  def start_node(node_id, topology = %Topology{}) when is_node_id(node_id) do
    Flock.Log.append(node_id, {:start_node, :requested})

    case NodesSupervisor.start_node(node_id, topology) do
      {:ok, pid} ->
        Flock.Log.append(node_id, {:start_node, :ok})
        {:ok, pid}

      {:error, error} ->
        Flock.Log.append(node_id, {:start_node, {:error, error}})
        {:error, translate_error(error)}
    end
  end

  def stop_node(node_id) do
    Flock.Log.append(node_id, {:stop_node, :requested})
    result = NodesSupervisor.stop_node(node_id)

    case result do
      :ok -> Flock.Log.append(node_id, {:stop_node, :ok})
      {:error, error} -> Flock.Log.append(node_id, {:stop_node, {:error, error}})
    end

    result
  end

  def leader(node_id) do
    NodeServer.leader(node_id)
  end

  defp translate_error({
         :shutdown,
         {
           :failed_to_start_child,
           {:via, Registry, {Flock.Registry, {_node_id, Acceptor}}},
           {:port_not_available, port}
         }
       }) do
    {:port_not_available, port}
  end

  defp translate_error(error), do: error
end
