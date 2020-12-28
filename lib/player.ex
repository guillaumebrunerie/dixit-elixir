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
    # The process waiting for messages from the network: TODO: do not use spawn
    spawn(fn -> Dixit.Network.init(args) end)
    {:ok, args}
  end

  # Received a message from the player
  @impl true
  def handle_call({:received, message}, _from, args) do
    case Dixit.Command.parse(message) do
      {:ok, command} ->
        case Dixit.GameRegister.run(command) do
          {:ok, state, hand} ->
            Dixit.Network.send_message(Dixit.Command.format_state(state), args)
            if hand !== nil && hand !== true, do: send_commands({:cards, hand}, args)
            {:reply, :ok, args}
          {:error, e} -> {:reply, {:error, e}, args}
        end
      e -> {:reply, e, args}
    end
  end

  # Received a message from the server
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

  def send_command(command, id) do
    message = Dixit.Command.format(command)
    GenServer.call(id, {:send, message})
  end
end
