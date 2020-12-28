defmodule Dixit.Player do
  @moduledoc """
  Receives messages from the websocket library and sends them to the logic,
  and vice versa.
  """

  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(args) do
    args = Map.put(args, :parent, self())
    # The process waiting for messages from the network
    spawn(fn -> Dixit.Network.init(args) end)
    {:ok, args}
  end

  @impl true
  def handle_call({:received, message}, _from, args) do
    response =
      with {:ok, command} <- Dixit.Command.parse(message),
      do:  Dixit.Command.run(command)

    case response do
      {:ok, state, hand} ->
        broadcast_state(state, args)
        if hand == true, do: broadcast_hands(state, args)
        if hand !== nil && hand !== true, do: send_commands({:cards, hand}, args)
      {:error, e} -> Dixit.Network.send_message("ERROR #{e}", args)
    end

    {:reply, :ok, args}
  end

  @impl true
  def handle_call({:send, message}, _from, args) do
    Dixit.Network.send_message(message, args)
    {:reply, :ok, args}
  end

  @impl true
  def handle_call({:send_state, state}, _from, args) do
    Dixit.Network.send_message(Dixit.Command.format_state(state), args)
    {:reply, :ok, args}
  end

  defp send_commands(command, args) do
    cond do
      is_list(command) -> Enum.each(command, &send_commands(&1, args))
      true -> Dixit.Network.send_message(Dixit.Command.format(command), args)
    end
  end

  defp broadcast_state(state, args) do
    Dixit.Network.send_message(Dixit.Command.format_state(state), args)
    Enum.each(state.players,
      fn player ->
        pid = Enum.find_value(state.pids, fn {pid, name} -> name === player && pid end)
        if pid != self(), do: GenServer.call(pid, {:send_state, state})
      end)
  end

  defp broadcast_hands(state, args) do
    Enum.each(state.hands,
      fn {player, hand} ->
        pid = Enum.find_value(state.pids, fn {pid, name} -> name === player && pid end)
        message = Dixit.Command.format({:cards, hand})
        if pid != self() do
          GenServer.call(pid, {:send, message})
        else
          Dixit.Network.send_message(message, args)
        end
      end)
  end

  def send_command(command, id) do
    message = Dixit.Command.format(command)
    GenServer.call(id, {:send, message})
  end
end
