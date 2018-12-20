defmodule Flock.TopologyTest do
  use ExUnit.Case
  alias Flock.Topology

  @json_config """
  {
    "node1": {"ip": "127.0.0.1", "port": 54130},
    "node2": {"ip": "127.0.0.1", "port": 54131},
    "node3": {"ip": "127.0.0.1", "port": 54132}
  }
  """

  @topology %Topology{
    nodes: %{
      "node1" => %Topology.Node{ip: {127, 0, 0, 1}, port: 54_130},
      "node2" => %Topology.Node{ip: {127, 0, 0, 1}, port: 54_131},
      "node3" => %Topology.Node{ip: {127, 0, 0, 1}, port: 54_132}
    }
  }

  test "decode json config" do
    assert Topology.from_json(@json_config) == @topology
  end

  test "peer_ids" do
    assert Topology.peer_ids(@topology, "node1") == ["node2", "node3"]
  end

  test "fetch_node" do
    assert Topology.fetch_node(@topology, "node1") ==
             {:ok, %Flock.Topology.Node{ip: {127, 0, 0, 1}, port: 54_130}}

    assert Topology.fetch_node(@topology, "loch-ness") == :error
  end

  test "candidate_ids" do
    assert Topology.candidate_ids(@topology, "node1") == ["node2", "node3"]
    assert Topology.candidate_ids(@topology, "node2") == ["node3"]
    assert Topology.candidate_ids(@topology, "node3") == []
  end
end
