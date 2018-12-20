defmodule Flock.CLI do
  @moduledoc "The CLI for Flock"
  alias Flock.Topology

  def main(args \\ []) do
    pretty_print_log_output()
    %{topology: topology, nodes: node_ids} = parse_args(args)

    Enum.each(node_ids, fn node_id ->
      {:ok, _pid} = Flock.start_node(node_id, topology)
    end)

    Process.sleep(:infinity)
  end

  defp pretty_print_log_output() do
    {:ok, pretty_printer} = Flock.Log.PrettyPrinter.start_link()
    Flock.Log.add_sink(pretty_printer)
  end

  defp parse_args(args) do
    {opts, _, _} =
      OptionParser.parse(args, switches: [upcase: :boolean, strict: [:topology, :nodes]])

    Enum.into(opts, %{}, fn {arg, value} ->
      {arg, prepare_arg(arg, value)}
    end)
  end

  @spec prepare_arg(:topology, String.t()) :: Topology.t()
  defp prepare_arg(:topology, path) do
    case File.read(Path.expand(path)) do
      {:ok, json} -> Topology.from_json(json)
      _ -> raise "Unable to read topology from #{path}"
    end
  end

  @spec prepare_arg(:nodes, String.t()) :: list(String.t())
  defp prepare_arg(:nodes, nodes_text) do
    String.split(nodes_text, ",")
  end
end
