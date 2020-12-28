defmodule Dixit.Application do
  @moduledoc """
  Main server.
  """

  require Logger
  use Application
  
  @doc """
  Entry point of the server.
  Starts
  - the game logic
  - the supervisor for the players
  - the tasks listening for incoming connections
  """
  def start(_type, _args) do
    children = [
      {Dixit.GameLogic,    name: Dixit.GameLogic, random: true},
#      {Dixit.GameRegister, name: Dixit.GameRegister},
      {DynamicSupervisor, strategy: :one_for_one, name: Dixit.PlayerSupervisor},
      Supervisor.child_spec({Task, fn -> listen(4020, true)  end}, id: Dixit.Listener1), # WebSockets
      Supervisor.child_spec({Task, fn -> listen(4000, false) end}, id: Dixit.Listener2), # Plain text
    ]

    opts = [strategy: :rest_for_one, name: Dixit.MainSupervisor]
    Supervisor.start_link(children, opts)
  end

  defp listen(port, ws?) do
    # The options below mean:
    #
    # 1. `:binary` - receives data as binaries (instead of lists)
    # 2. `packet: :line` - receives data line by line
    # 3. `active: false` - blocks on `:gen_tcp.recv/2` until data is available
    # 4. `reuseaddr: true` - allows us to reuse the address if the listener crashes
    #
    {:ok, listen_socket} =
      :gen_tcp.listen(port, [:binary, packet: :line, active: :false, reuseaddr: true])
    IO.puts("Accepting connections on port #{port} (#{if ws?, do: "WebSockets", else: "plain text"})")
    loop_acceptor(listen_socket, ws?)
  end

  defp loop_acceptor(listen_socket, ws?) do
    IO.puts("Waiting for client")
    {:ok, socket} = :gen_tcp.accept(listen_socket)
    IO.puts("Found client!")
    {:ok, pid} = DynamicSupervisor.start_child(Dixit.PlayerSupervisor, {Dixit.Player, %{ws?: ws?, socket: socket}})
    :ok = :gen_tcp.controlling_process(socket, pid)
    loop_acceptor(listen_socket, ws?)
  end
end
