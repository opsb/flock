defmodule Flock.Protocol do
  alias Flock.Topology
  @moduledoc "Specifies the message format for Flock"
  @type request ::
          :alive?
          | :ping
          | {:iamtheking, Topology.node_id()}

  @type response ::
          :finethanks
          | :pong

  @spec encode_request(request) :: String.t()
  def encode_request(:alive?), do: "ALIVE"
  def encode_request(:ping), do: "PING"
  def encode_request({:iamtheking, leader_id}), do: "IAMTHEKING:#{leader_id}"

  @spec decode_request(String.t()) :: request
  def decode_request("ALIVE"), do: :alive?
  def decode_request("PING"), do: :ping
  def decode_request("IAMTHEKING:" <> leader_id), do: {:iamtheking, leader_id}

  @spec encode_response(response) :: String.t()
  def encode_response(:finethanks), do: "FINETHANKS"
  def encode_response(:pong), do: "PONG"

  @spec decode_response(String.t()) :: response
  def decode_response("FINETHANKS"), do: :finethanks
  def decode_response("PONG"), do: :pong
end
