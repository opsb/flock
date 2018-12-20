defmodule Flock.Tcp.Util do
  @moduledoc "Utilities for working with gen_tcp"
  def find_available_port() do
    {:ok, port} = :gen_tcp.listen(0, [])
    {:ok, port_number} = :inet.port(port)
    Port.close(port)
    port_number
  end
end
