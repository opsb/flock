defmodule Flock.NodeServerTest do
  use ExUnit.Case
  alias Flock.Topology
  alias Flock.NodeServer

  @node_timeout 200
  @message_timeout @node_timeout * 2

  @topology %Topology{
    nodes: %{
      "node1" => %Topology.Node{ip: {127, 0, 0, 1}, port: 54_130},
      "node2" => %Topology.Node{ip: {127, 0, 0, 1}, port: 54_131},
      "node3" => %Topology.Node{ip: {127, 0, 0, 1}, port: 54_132}
    }
  }

  def start_node(node_id, topology) do
    test_pid = self()
    send_message = fn args -> send(test_pid, {:send_message, args}) end
    assert {:ok, pid} = NodeServer.start_link(node_id, topology, send_message, @node_timeout)
    assert Process.alive?(pid)
  end

  def follow_leader(node_id, leader: leader_id) do
    NodeServer.handle_request(node_id, "IAMTHEKING:#{leader_id}")
  end

  def trigger_election(node_id) do
    NodeServer.handle_request(node_id, "ALIVE?")
  end

  test "ping" do
    start_node("node1", @topology)
    follow_leader("node1", leader: "node3")
    flush_mailbox()

    assert_receive(
      {:send_message, from: "node1", to: "node3", message: "PING"},
      @message_timeout
    )
  end

  test "become leader after nobody responds to ALIVE?" do
    start_node("node1", @topology)
    flush_mailbox()
    trigger_election("node1")

    assert_receive(
      {:send_message, from: "node1", to: ["node2", "node3"], message: "IAMTHEKING:node1"},
      @message_timeout
    )

    assert NodeServer.leader("node1") == "node1"
  end

  test "follow leader that responds to ALIVE?" do
    start_node("node1", @topology)
    flush_mailbox()
    trigger_election("node1")

    assert_receive(
      {:send_message, from: "node1", to: ["node2", "node3"], message: "ALIVE?"},
      @message_timeout
    )

    NodeServer.handle_request("node1", "IAMTHEKING:node3")
    assert NodeServer.leader("node1") == "node3"
  end

  test "restart election when leader confirmation times out" do
    start_node("node1", @topology)
    trigger_election("node1")

    flush_mailbox()
    NodeServer.handle_response("node1", "FINETHANKS")

    assert_receive(
      {:send_message, from: "node1", to: ["node2", "node3"], message: "ALIVE?"},
      @message_timeout
    )
  end

  test "handle ALIVE? when lowest node" do
    start_node("node1", @topology)
    flush_mailbox()

    {:response, "FINETHANKS"} = NodeServer.handle_request("node1", "ALIVE?")

    assert_receive(
      {:send_message, from: "node1", to: ["node2", "node3"], message: "ALIVE?"},
      @message_timeout
    )
  end

  test "handle ALIVE? when highest node" do
    start_node("node3", @topology)
    flush_mailbox()

    {:response, "FINETHANKS"} = NodeServer.handle_request("node3", "ALIVE?")

    assert_receive(
      {:send_message, from: "node3", to: ["node1", "node2"], message: "IAMTHEKING:node3"},
      @message_timeout
    )

    refute_receive({:send_message, from: "node1", to: ["node2", "node3"], message: "ALIVE?"})
  end

  test "remembers leader after receiving IAMTHEKING" do
    start_node("node1", @topology)
    flush_mailbox()

    NodeServer.handle_request("node1", "IAMTHEKING:node3")
    assert NodeServer.leader("node1") == "node3"
  end

  test "initiates election when joining" do
    start_node("node1", @topology)

    assert_receive(
      {:send_message, from: "node1", to: ["node2", "node3"], message: "ALIVE?"},
      @message_timeout
    )
  end

  def flush_mailbox(messages \\ []) do
    receive do
      message -> flush_mailbox(messages ++ [message])
    after
      0 -> messages
    end
  end
end
