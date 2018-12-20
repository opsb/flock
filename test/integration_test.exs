defmodule IntegrationTest do
  use ExUnit.Case

  alias Flock.Topology

  test "leader switching" do
    Flock.Log.add_sink(self())

    topology = %Topology{
      nodes: %{
        "node1" => %Topology.Node{ip: {127, 0, 0, 1}, port: Flock.Tcp.Util.find_available_port()},
        "node2" => %Topology.Node{ip: {127, 0, 0, 1}, port: Flock.Tcp.Util.find_available_port()},
        "node3" => %Topology.Node{ip: {127, 0, 0, 1}, port: Flock.Tcp.Util.find_available_port()}
      }
    }

    # start all nodes
    {:ok, _node1} = Flock.start_node("node1", topology)
    {:ok, _node2} = Flock.start_node("node2", topology)
    {:ok, _node3} = Flock.start_node("node3", topology)

    # wait until leader has propagated
    wait_for_new_leader("node1")
    wait_for_new_leader("node2")

    # confirm all nodes have correct leader
    assert Flock.leader("node1") == "node3"
    assert Flock.leader("node2") == "node3"
    assert Flock.leader("node3") == "node3"

    # kill the current leader
    Flock.stop_node("node3")

    # wait for propagation
    wait_for_new_leader("node1")

    # confirm both nodes have adopted new leader
    assert Flock.leader("node1") == "node2"
    assert Flock.leader("node2") == "node2"

    # restart the previous leader
    Flock.start_node("node3", topology)

    # wait for propagation
    wait_for_new_leader("node1")
    wait_for_new_leader("node2")

    # confirm all nodes have reverted back to the original leader
    assert Flock.leader("node1") == "node3"
    assert Flock.leader("node2") == "node3"
    assert Flock.leader("node3") == "node3"

    # stop the nodes
    Flock.stop_node("node1")
    Flock.stop_node("node2")
    Flock.stop_node("node3")
  end

  def wait_for_new_leader(node_id) do
    assert_receive({:flock, ^node_id, {:following, _leader_id}}, 5000)
  end
end
