defmodule Flock.Log.PrettyPrinter do
  @moduledoc "Pretty prints Flock log messages"
  use GenServer
  alias Flock.Topology
  import Flock.Topology, only: [is_node_id: 1]
  import Flock.Protocol, only: [encode_request: 1, encode_response: 1]

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

  @spec format({:flock, Topology.node_id(), Flock.Log.entry()}) :: {:ok, String.t()} | :none
  defp format({:flock, node_id, log_entry}) when is_node_id(node_id) do
    case format_log_entry(log_entry) do
      {:ok, formatted} -> {:ok, prefixed(node_id, formatted)}
      :none -> :none
    end
  end

  defp format_log_entry({:start_node, :requested}) do
    {:ok, "started"}
  end

  defp format_log_entry({:received, response, [from: sender_id]}) do
    {:ok, "received #{encode_response(response)} from #{sender_id}"}
  end

  defp format_log_entry({:sent, request, [to: recipient_id]}) do
    {:ok, "sent #{encode_request(request)} to #{format_recipients(recipient_id)}"}
  end

  defp format_log_entry({:stop_node, :ok}) do
    {:ok, "stopped"}
  end

  defp format_log_entry(:became_leader) do
    {:ok, "became leader"}
  end

  defp format_log_entry({:following, leader_id}) do
    {:ok, "following #{leader_id}"}
  end

  defp format_log_entry({:received_request, [request: request]}) do
    {:ok, "request: #{encode_request(request)}"}
  end

  defp format_log_entry({:handled_request, [request: _request, response: response]})
       when response != :noresponse do
    {:ok, "response: #{encode_response(response)}"}
  end

  defp format_log_entry(_message) do
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
