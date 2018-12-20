defmodule Flock.Log.PrettyPrinter do
  @moduledoc "Pretty prints Flock log messages"
  use GenServer
  import Flock.Topology, only: [is_node_id: 1]

  def start_link() do
    GenServer.start_link(__MODULE__, :nostate)
  end

  @impl GenServer
  def init(state) do
    {:ok, state}
  end

  @impl GenServer
  def handle_info(message, :nostate) do
    case format(message) do
      {:ok, formatted} -> IO.puts(formatted)
      :none -> :ok
    end

    {:noreply, :nostate}
  end

  defp format({:flock, node_id, {:start_node, :requested}}) when is_node_id(node_id) do
    {:ok, prefixed(node_id, "started")}
  end

  defp format({:flock, node_id, {:received, message, [from: sender_id]}})
       when is_node_id(node_id) do
    {:ok, prefixed(node_id, "received #{message} from #{sender_id}")}
  end

  defp format({:flock, node_id, {:sent, message, [to: recipient_id]}}) when is_node_id(node_id) do
    {:ok, prefixed(node_id, "sent #{message} to #{format_recipients(recipient_id)}")}
  end

  defp format({:flock, node_id, {:stop_node, :ok}}) when is_node_id(node_id) do
    {:ok, prefixed(node_id, "stopped")}
  end

  defp format({:flock, node_id, :became_leader}) when is_node_id(node_id) do
    {:ok, prefixed(node_id, "became leader")}
  end

  defp format({:flock, node_id, {:following, leader_id}}) when is_node_id(node_id) do
    {:ok, prefixed(node_id, "following #{leader_id}")}
  end

  defp format({:flock, node_id, {:received_request, [request: request]}})
       when is_node_id(node_id) do
    {:ok, prefixed(node_id, "request: #{request}")}
  end

  defp format({:flock, node_id, {:handled_request, [request: _request, response: response]}})
       when is_node_id(node_id) and response != :noresponse do
    {:ok, prefixed(node_id, "response: #{response}")}
  end

  defp format(_message) do
    :none
  end

  defp format_recipients(recipients) when is_list(recipients) do
    Enum.join(recipients, ",")
  end

  defp format_recipients(recipient), do: recipient

  defp prefixed(node_id, message) do
    "#{node_id}> #{message}"
  end
end
