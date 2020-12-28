defmodule Dixit.GameRegister do
  @moduledoc """
  Maps players to games.

  We need to map a pid of a player to its eventual game pid and eventual name
  """
  
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok) do
    {:ok, %{}}
  end

  # TODO: New game, join game, etc…
  
  @impl true
  def handle_call({:name, name}, {pid, _}, register) do
    if (Map.get(register, pid) != nil) do
      {:reply, {:error, :duplicate_name_command}, register}
    else
      register = put_in(register[pid], name)
      {state, hand} =
      if Dixit.GameLogic.has_player?(Dixit.GameLogic, name) do
        IO.puts("[GR] Existing player: #{name}")
        {Dixit.GameLogic.get_state(Dixit.GameLogic), nil}
      else
        IO.puts("[GR] New player: #{name} / #{inspect pid}")
        {:ok, state, hand} = Dixit.GameLogic.new_player(Dixit.GameLogic, name)
        broadcast_state(state, register, pid)
        {state, hand}
      end
      {:reply, {:ok, state, hand}, register}
    end
  end

  def handle_call(command, {pid, _}, register) do
    case Map.get(register, pid) do
      nil -> {:reply, {:error, :no_name_yet}, register}
      player ->
        case Dixit.GameLogic.run_command(Dixit.GameLogic, player, command) do
          {:ok, state, hand} ->
            broadcast_state(state, register, pid)
            hand = if hand == true do
              broadcast_hands(state, register, pid)
              state.hands[player]
            else
              nil
            end
            {:reply, {:ok, state, hand}, register}
          {:error, e} -> {:reply, {:error, e}, register}
        end
    end
  end

  defp broadcast_state(state, register, origin_pid) do
    Enum.each(register,
      fn {pid, name} ->
        if pid != origin_pid, do: GenServer.call(pid, {:send_state, state})
      end)
  end

  defp broadcast_hands(state, register, origin_pid) do
    Enum.each(state.hands,
      fn {player, hand} ->
        pid = Enum.find_value(register, fn {pid, name} -> name === player && pid end)
        message = Dixit.Command.format({:cards, hand})
        if pid != origin_pid do
          GenServer.call(pid, {:send, message})
        end
      end)
  end

  def run(command) do
    GenServer.call(Dixit.GameRegister, command)
  end
end
