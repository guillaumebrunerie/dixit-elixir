defmodule Dixit.NetworkListener do
  require Logger

  # I want to make a task with a permanent restart strategy and a custom id based on the arguments
  # I do not see how to use something along the lines of
  #
  #     use Task, restart: :permanent
  #
  # Therefore I just customize the [child_spec] function instead
  def child_spec(arg) do
    %{
      id: {__MODULE__, arg[:port]},
      start: {__MODULE__, :start_link, [arg]}
    }
  end

  def start_link(arg) do
    Task.start_link(__MODULE__, :listen, [arg])
  end

  # Start listening at port [port], expecting a WebSocket connection or a plain
  # text one depending on [ws?].
  def listen(port: port, ws?: ws?) do
    {:ok, listen_socket} =
      :gen_tcp.listen(port, [:binary, packet: :line, active: false, reuseaddr: true])

    Logger.info(
      "Accepting connections on port #{port} (#{if ws?, do: "WebSockets", else: "plain text"})"
    )
    loop_acceptor(listen_socket, ws?)
  end

  defp loop_acceptor(listen_socket, ws?) do
    {:ok, socket} = :gen_tcp.accept(listen_socket)

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Dixit.PlayerSupervisor,
        {Dixit.Player, %{ws?: ws?, socket: socket}}
      )

    Logger.info("New client connected")
    :ok = :gen_tcp.controlling_process(socket, pid)
    loop_acceptor(listen_socket, ws?)
  end
end
