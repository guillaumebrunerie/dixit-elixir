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
      {:ok, pid} = DynamicSupervisor.start_child(Dixit.GameLogicSupervisor, {Dixit.GameLogic, random: true, deck_size: 106})
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

    state = if existing_player? do
      Logger.info("[GR] Existing player: #{name}")
      Dixit.GameLogic.get_state(register.games[game].gamepid)
    else
      Logger.info("[GR] New player: #{name} / #{inspect pid}")
      {:ok, state} = Dixit.GameLogic.new_player(register.games[game].gamepid, name)
      Enum.each(register.games[game].players,
        fn {player, pid} ->
          if player !== name && Process.alive?(pid), do: GenServer.call(pid, {:send, :players, state, nil})
        end)
      state
    end
    {:reply, {:ok, state, name}, register}
  end

  @impl true
  def handle_call({:broadcast, item, state}, {pid, _}, register) do
    {game, _} = Enum.find(register.games, fn {_, g} -> g.gamepid == pid end)
    Enum.each(register.games[game].players,
      fn {player, pid} ->
        if Process.alive?(pid), do: GenServer.call(pid, {:send, item, state, player})
      end)
    {:reply, :ok, register}
  end

  @impl true
  def handle_call(command, {pid, _}, register) do
    case register.players[pid] do
      nil -> {:reply, {:error, :no_name_yet}, register}
      %{name: name, game: game} ->
        case Dixit.GameLogic.run_command(register.games[game].gamepid, name, command) do
          :ok ->
            {:reply, :ok, register}
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

  def broadcast({item, state}) do
    GenServer.call(Dixit.GameRegister, {:broadcast, item, state})
  end
end
