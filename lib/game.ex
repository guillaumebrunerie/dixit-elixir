defmodule Dixit.GameLogic do
  @moduledoc """
  Server for a game
  """

  @deckSize 106
  
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok) do
    deck = Enum.shuffle(1..@deckSize)
    {:ok, %{:pids => %{}, :players => %{}, :gstate => nil, :deck => deck}}
  end

  def pick_hand([a, b, c, d, e] ++ t) do
    {:ok, {[a, b, c, d, e] , t}}
  end

  def check_vote_end({:voting, {teller, answer}, selecters, cards, voters} = gstate, players) do
    all_non_nil = Enum.reduce(Map.values(voters), true, fn v, acc -> acc and v != nil end)
    if all_non_nil do
      evaluate = fn card ->
        origin = if card == answer do
            teller
          else
            Enum.find(selecters, fn {_, v} -> v == card end)
            |> elem(1)
          end
        votes =
          voters
          |> Enum.filter(fn {_, v} -> v == card end)
          |> Enum.map(fn {k, _} -> k end)
        %{:origin => origin, :votes => votes}
      end
      {:next_round, Map.new(cards, evaluate), players}
    else
      gstate
    end
  end

  def check_select_end({:selecting, {teller, answer}, splayers} = gstate) do
    all_non_nil = Enum.reduce(Map.values(splayers), true, fn v, acc -> acc and v != nil end)
    if all_non_nil do
      cards = Enum.shuffle([ answer | Map.values(splayers) ])
      {:voting, {teller, answer}, splayers, cards, Enum.reduce(splayers, %{}, (fn {k, _}, acc -> Map.put(acc, k, nil) end))}
    else
      gstate
    end
  end

  @impl true
  def handle_call({:vote, card, _socket}, {pid, _}, state) do
    player = state.pids[pid]
    case state.gstate do
      {:voting, nc, splayers, cards, voters} ->
        if (Map.has_key?(voters, player)) do
          gstate = check_vote_end({:voting, nc, splayers, cards, %{voters | player => card}}, Map.keys(state.players))
          broadcast(gstate, state.players)
          {:reply, :ok, %{state | gstate: gstate}}
        else
          {:reply, {:error, :not_your_turn_to_vote}, state}
        end
      _ -> {:reply, {:error, :wrong_game_state}, state}
    end
  end
  
  @impl true
  def handle_call({:select, card, _socket}, {pid, _}, state) do
    player = state.pids[pid]
    case state.gstate do
      {:selecting, nc, splayers} ->
        if (Map.has_key?(splayers, player)) do
          gstate = check_select_end({:selecting, nc, %{splayers | player => card}})
          broadcast(gstate, state.players)
          {:reply, :ok, %{state | gstate: gstate}}
        else
          {:reply, {:error, :not_your_turn_to_select}, state}
        end
      _ -> {:reply, {:error, :wrong_game_state}, state}
    end
  end
  
  @impl true
  def handle_call({:tell, card, _socket}, {pid, _}, state) do
    case state.gstate do
      {:telling, name} ->
        if (name == state.pids[pid]) do
          other_players = state.players |> Map.keys |> Enum.filter(fn n -> n != name end)
          gstate = {:selecting, {name, card}, Enum.reduce(other_players, %{}, (fn k, acc -> Map.put(acc, k, nil) end))}
          broadcast(gstate, state.players)
          {:reply, :ok, %{state | gstate: gstate}}
        else
          {:reply, {:error, :not_your_turn_to_tell}, state}
        end
      _ ->
        {:reply, {:error, :wrong_game_state}, state}
    end
  end
  
  @impl true
  def handle_call({:name, name, socket}, {pid, _}, state) do
    cond do
      # Check that the pid does not already exist
      Map.get(state.pids, pid) != nil ->
        {:reply, {:error, :duplicate_name_command}, state}
        
      true ->
        # Create a new player, or fetch the existing one and update the socket
        {new_player, deck} =
          case Map.get(state.players, name) do
            nil ->
              IO.puts("New player: #{name}")
              {:ok, {hand, deck}} = pick_hand(state.deck)
              {%{:socket => socket, :score => 0, :cards => hand}, deck}
            player ->
              IO.puts("Existing player: #{name}")
              {%{player | :socket => socket}, state.deck}
          end
        players = Map.put(state.players, name, new_player)
        pids = Map.put(state.pids, pid, name)
        gstate = state.gstate || {:telling, name}

        # Tell all other players about the new player
        broadcast({:players, players}, players)
        narrowcast({:cards, new_player.cards}, new_player)
        narrowcast(gstate, new_player)

        # Update the state
        {:reply, :ok, %{state | players: players, pids: pids, deck: deck, gstate: gstate}}
    end
  end

  def broadcast(command, players) do
    message = Dixit.Command.format(command)
    Enum.each(players,
      fn {_name, player} -> Dixit.Player.write_command(message, player.socket)
      end)
  end

  def narrowcast(command, player) do
    message = Dixit.Command.format(command)
    Dixit.Player.write_command(message, player.socket)
  end


  def run_name(name, socket) do
    GenServer.call(Dixit.GameLogic, {:name, name, socket})
  end

  def run_tell(card, socket) do
    GenServer.call(Dixit.GameLogic, {:tell, card, socket})
  end

  def run_select(card, socket) do
    GenServer.call(Dixit.GameLogic, {:select, card, socket})
  end

  def run_vote(card, socket) do
    GenServer.call(Dixit.GameLogic, {:vote, card, socket})
  end
end
