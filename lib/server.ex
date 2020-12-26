defmodule Dixit.MainServer do
  @moduledoc """
  Main server.
  """

  require Logger
  use Application

  @doc """
  Entry point of the server.
  Starts the supervisor for the players and the task listening to incoming connections.
  """
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: Dixit.PlayerSupervisor},
      {Task, fn -> listen(4000) end},
      {Dixit.GameLogic, name: Dixit.GameLogic},
    ]

    opts = [strategy: :one_for_one, name: Dixit.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp listen(port) do
    # The options below mean:
    #
    # 1. `:binary` - receives data as binaries (instead of lists)
    # 2. `packet: :line` - receives data line by line
    # 3. `active: false` - blocks on `:gen_tcp.recv/2` until data is available
    # 4. `reuseaddr: true` - allows us to reuse the address if the listener crashes
    #
    {:ok, socket} =
      :gen_tcp.listen(port, [:binary, packet: :line, active: false, reuseaddr: true])
    IO.puts("Accepting connections on port #{port}")
    loop_acceptor(socket)
  end

  defp loop_acceptor(socket) do
    IO.puts("Waiting for client")
    {:ok, client} = :gen_tcp.accept(socket)
    IO.puts("Found client!")
    {:ok, pid} = Task.Supervisor.start_child(Dixit.PlayerSupervisor,
      fn -> Dixit.Player.connect(client) end)
    :ok = :gen_tcp.controlling_process(client, pid)
    loop_acceptor(socket)
  end
end
