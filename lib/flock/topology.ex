defmodule Flock.Topology do
  use TypedStruct

  @moduledoc "Represents the structure of a cluster"

  @type node_id :: String.t()

  typedstruct do
    field(:nodes, %{String.t() => Node.t()}, enforce: true)
  end

  defmodule Node do
    @moduledoc "Network details for cluster node"
    typedstruct do
      field(:ip, :inet.ip4_address())
      field(:port, integer())
    end
  end

  defmacro is_node_id(node_id) do
    quote do
      is_binary(unquote(node_id))
    end
  end

  def fetch_node(topology = %__MODULE__{}, node_id) when is_node_id(node_id) do
    Map.fetch(topology.nodes, node_id)
  end

  def peer_ids(topology = %__MODULE__{}, node_id) when is_node_id(node_id) do
    topology.nodes
    |> Map.delete(node_id)
    |> Map.keys()
  end

  def candidate_ids(topology = %__MODULE__{}, node_id) when is_node_id(node_id) do
    topology.nodes
    |> Map.keys()
    |> Enum.filter(fn k -> k > node_id end)
  end

  def from_json(json) when is_binary(json) do
    nodes =
      json
      |> Poison.decode!()
      |> Enum.into(%{}, &decode_json_node/1)

    %__MODULE__{nodes: nodes}
  end

  defp decode_json_node({node_id, %{"ip" => ip_text, "port" => port}}) do
    {:ok, ip} = decode_json_ip(ip_text)
    {node_id, %Node{ip: ip, port: port}}
  end

  defp decode_json_ip(json) do
    json
    |> to_charlist()
    |> :inet.parse_ipv4_address()
  end
end
