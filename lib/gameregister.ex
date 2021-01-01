defmodule Dixit.GameRegister do
  @moduledoc """
  Maps players to games.

  In the register we store

  players: map from player pid to %{name: name, game: game}
  games:   map from game to %{gamepid: pid, players: map names -> pids}

  Things that can happen:
  - a players connects
  - a player disconnects
  """

  use GenServer

  require Logger
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok) do
    Logger.info("Hello from the GameRegister")
    {:ok, %{players: %{}, games: %{}}}
  end

  def ensure_game_exists(register, game) do
    if register.games[game] == nil do
      {:ok, pid} = DynamicSupervisor.start_child(Dixit.GameLogicSupervisor, {Dixit.GameLogic, random: true})
      put_in(register.games[game], %{gamepid: pid, players: %{}})
    else
      register
    end
  end

  # def ensure_game_exists2(game) do
  #   if Registry.lookup(Dixit.GameRegistry, game) == [] do
  #     {:ok, pid} = DynamicSupervisor.start_child(Dixit.GameLogicSupervisor, {Dixit.GameLogic, random: true, name: game})
  # end
  
  @impl true
  def handle_call({:join_game, game, name}, {pid, _}, register) do
    existing_player? =
      game in Map.keys(register.games) &&
      name in Map.keys(register.games[game].players)

    register =
      register
      |> ensure_game_exists(game)
      |> put_in([:players, pid], %{name: name, game: game})
      |> put_in([:games, game, :players, name], pid)

    if existing_player? do
      Logger.info("[GR] Existing player: #{name}")
      state = Dixit.GameLogic.get_state(register.games[game].gamepid)
      hand = state.hands[name]
      {:reply, {:ok, state, hand}, register}
    else
      Logger.info("[GR] New player: #{name} / #{inspect pid}")
      {:ok, state, hand} = Dixit.GameLogic.new_player(register.games[game].gamepid, name)
      broadcast_state(state, register, game, name)
      {:reply, {:ok, state, hand}, register}
    end
  end

  def handle_call(command, {pid, _}, register) do
    case register.players[pid] do
      nil -> {:reply, {:error, :no_name_yet}, register}
      %{name: name, game: game} ->
        case Dixit.GameLogic.run_command(register.games[game].gamepid, name, command) do
          {:ok, state, hand} ->
            broadcast_state(state, register, game, name)
            hand = if hand == true do
              broadcast_hands(state, register, game, name)
              state.hands[name]
            else
              nil
            end
            {:reply, {:ok, state, hand}, register}
          {:error, e} -> {:reply, {:error, e}, register}
        end
    end
  end

  def run(command) do
    GenServer.call(Dixit.GameRegister, command)
  end

  # def run(command) do
  #   case Registry.select(Dixit.PlayerRegistry, {{:_, :"$1", :"$2"}, [], [:"$1"]}) do
  #     [] -> nil
  #     [pid] ->

  defp broadcast_state(state, register, game, name) do
    Enum.each(register.games[game].players,
      fn {player, pid} ->
        if player != name && Process.alive?(pid), do: GenServer.call(pid, {:send_state, state})
      end)
  end

  defp broadcast_hands(state, register, game, name) do
    Enum.each(register.games[game].players,
      fn {player, pid} ->
        if player != name && Process.alive?(pid) do
          GenServer.call(pid, {:send, Dixit.Command.format({:cards, state.hands[player]})})
        end
      end)
  end
end
