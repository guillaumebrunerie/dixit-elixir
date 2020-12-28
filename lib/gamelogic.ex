defmodule Dixit.GameLogic do
  @moduledoc """
  Implementation of the game logic.
  """

  @deckSize 106
  
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, opts)
  end

  @impl true
  def init(opts) do
    deck = 1..@deckSize
    deck = if (opts[:random]) do
      Enum.shuffle(deck)
    else
      Enum.to_list(deck)
    end
    {:ok, %{players: [],
            scores: %{},
            hands: %{},
            deck: deck,
            phaseT: nil,
           }
    }
  end

  def pick_hand([a, b, c, d, e, f] ++ t) do
    {[a, b, c, d, e, f] , t}
  end

  def pick_card([a] ++ t) do
    {:ok, {a , t}}
  end

  @impl true
  def handle_call({:get_state}, _, state) do
    {:reply, {:ok, state}, state}
  end

  def get_state(logic) do
    GenServer.call(logic, {:get_state})
  end
  
  @impl true
  def handle_call({:new_player, name}, _, state) do
    {hand, deck} = pick_hand(state.deck)
    state = state
    |> put_in([:scores, name], 0)
    |> put_in([:hands, name], hand)
    |> put_in([:deck], deck)
    |> put_in([:players], [name | state.players])
    |> update_in([:phaseT], &(&1 || %{teller: name, phaseS: nil}))
    {:reply, {:ok, state, hand}, state}
  end

  # @impl true
  # def handle_call({:name, name}, {pid, _}, state) do
  #   cond do
  #     # Check that the pid does not already exist
  #     Map.get(state.pids, pid) != nil ->
  #       {:reply, {:error, :duplicate_name_command}, state}
  #     true ->
  #       state =
  #       if Enum.member?(state.players, name) do
  #         IO.puts("Existing player: #{name}")
  #         put_in(state.pids[pid], name)
  #       else
  #         IO.puts("New player: #{name} with pid #{inspect pid}")
  #         {hand, deck} = pick_hand(state.deck)
  #         state
  #         |> put_in([:pids, pid], name)
  #         |> put_in([:scores, name], 0)
  #         |> put_in([:hands, name], hand)
  #         |> put_in([:deck], deck)
  #         |> put_in([:players], [name | state.players])
  #         |> update_in([:phaseT], &(&1 || %{teller: name, phaseS: nil}))
  #       end
  #       {:reply, {:ok, state, state.hands[name]}, state}
  #   end
  # end

  def new_player(logic, name) do
    GenServer.call(logic, {:new_player, name})
  end
  
  def run(state, player, {:tell, card}) do
    case state.phaseT do
      %{teller: teller, phaseS: nil} ->
        if (teller !== player) do
          {:error, :not_your_turn_to_tell}
        else
          other_players = Enum.filter(state.players, &(&1 != teller))
          selected = Map.new(other_players, &({&1, nil}))
          state = put_in(state.phaseT.phaseS, %{answer: card, selected: selected, phaseV: nil})
          {:ok, state, nil}
        end
      _ -> 
        {:error, :wrong_game_state}
    end
  end
  
  def run(state, player, {:select, card}) do
    case state.phaseT do
      %{teller: teller,
        phaseS: %{
          answer: answer,
          selected: selected,
          phaseV: nil
        }
      } ->
        if (!Map.has_key?(selected, player)) do
          {:error, :not_your_turn_to_select}
        else
          state = put_in(state.phaseT.phaseS.selected[player], card)
          selected = state.phaseT.phaseS.selected
          state = if has_nil(selected) do
            state
          else
            candidates = Enum.shuffle([answer | Map.values(selected)])
            votes = state.players
            |> Enum.filter(fn n -> n !== teller end)
            |> Map.new(&{&1, nil})
            put_in(state.phaseT.phaseS.phaseV,
              %{candidates: candidates,
                votes: votes,
                phaseR: nil})
          end
          {:ok, state, nil}
        end
      _ ->
        {:error, :wrong_game_state}
    end
  end

  def run(state, player, {:vote, card}) do
    case state.phaseT do
      %{teller: teller,
        phaseS: %{
           answer: answer,
           selected: selected,
           phaseV: %{
             candidates: candidates,
             votes: votes,
             phaseR: nil
           }
        }
      } -> if (!Map.has_key?(votes, player)) do
        {:error, :not_your_turn_to_vote}
      else
        state = put_in(state.phaseT.phaseS.phaseV.votes[player], card)
        votes = state.phaseT.phaseS.phaseV.votes
        state = if has_nil(votes) do
          state
        else
          evaluate = fn card ->
            origin = if card == answer do
                teller
              else
                Enum.find(selected, fn {_, v} -> v == card end)
                |> elem(0)
              end
            votes =
              votes
              |> Enum.filter(fn {_, v} -> v == card end)
              |> Enum.map(fn {k, _} -> k end)
            {origin, votes}
          end
          compute_scores(put_in(state.phaseT.phaseS.phaseV.phaseR,
            %{results: Map.new(candidates, evaluate),
              waiting: state.players}))
        end
        {:ok, state, nil}
      end
      _ -> {:error, :wrong_game_state}
    end
  end

  def run(state, player, {:nextround}) do
    case state.phaseT do
      %{phaseS: %{
          phaseV: %{
            phaseR: %{
              waiting: waiting,
            }
          }
        }
      } -> if (!Enum.member?(waiting, player)) do
        {:error, :already_clicked_next_round}
      else
        state = put_in(state.phaseT.phaseS.phaseV.phaseR.waiting,
            Enum.filter(waiting, &(&1 !== player)))
        {state, newround} = if state.phaseT.phaseS.phaseV.phaseR.waiting === [] do
          # New round
          {next_round(state), true}
        else
          {state, nil}
        end
        {:ok, state, newround}
      end
      _ ->        
        {:error, :wrong_game_state}
    end
  end

  defp next_in_list(l, v, first \\ nil)
  
  defp next_in_list([_], _, first) do
    first
  end

  defp next_in_list([h | [s | t]], v, first) do
    if (h === v) do
      s
    else
      next_in_list([s | t], v, first || h)
    end
  end

  def has_nil(map) do
    map |> Map.values |> Enum.member?(nil)
  end

  def next_round(state) do
    teller = state.phaseT.teller
    answer = state.phaseT.phaseS.answer
    selected = state.phaseT.phaseS.selected
    new_hands = Enum.reduce(state.hands, {:ok, state.deck, %{}},
      fn {player, hand}, {:ok, [card | deck], new_hands} -> (
          IO.puts("DEBUG: #{inspect hand} / #{inspect selected[player]}")
          new_hand = [card | List.delete(hand, (if player === teller, do: answer, else: selected[player]))]
          {:ok, deck, Map.put(new_hands, player, new_hand)})
        _ , _ ->
          IO.puts("Exhausted deck")
          :exhausted_deck
      end)
    case new_hands do
      {:ok, deck, hands} ->
        %{
          players: state.players,
          scores: state.scores,
          hands: hands,
          deck: deck,
          phaseT: %{
            teller: next_in_list(state.players, state.phaseT.teller),
            phaseS: nil
          }
        }
      :exhausted_deck ->
        %{
          players: state.players,
          scores: state.scores,
          hands: state.hands,
          deck: [],
          phaseT: nil
        }
    end
  end

  def compute_scores(state) do
    results = state.phaseT.phaseS.phaseV.phaseR.results
    teller = state.phaseT.teller
    votes_for_teller = length(results[teller])
    well_done = votes_for_teller > 0 && votes_for_teller < length(state.players) - 1
    scores = if well_done do
      # The teller and the players who found the correct image score 3 points
      Map.new(state.scores, fn {player, score} ->
        {player,
        if player === teller || Enum.member?(results[teller], player) do
          score + 3
        else
          score
        end}
      end)
    else
      # Everyone except the teller scores 2 points
      Map.new(state.scores, fn {player, score} ->
        {player,
        if player === teller do
          score
        else
          score + 2
        end}
      end)
    end
    # The players who got their image voted on score 1 point
    scores = Map.new(scores, fn {player, score} ->
      {player,
      if player === teller do
        score
      else
        score + length(results[player])
      end}
    end)
    %{state | scores: scores}
  end

  
  def run_name(name, logic) do
    GenServer.call(logic, {:name, name})
  end

  def run_tell(card, logic) do
    GenServer.call(logic, {:tell, card})
  end

  def run_select(card, logic) do
    GenServer.call(logic, {:select, card})
  end

  def run_vote(card, logic) do
    GenServer.call(logic, {:vote, card})
  end

  def run_nextround(logic) do
    GenServer.call(logic, {:nextround})
  end
  
  @impl true
  def handle_call({:command, name, command}, _, state) do
    case run(state, name, command) do
      {:ok, new_state, hand} ->
        {:reply, {:ok, new_state, hand}, new_state}
      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  def run_command(logic, name, command) do
    GenServer.call(logic, {:command, name, command})
  end
  
  @impl true
  def handle_call({:has_player?, name}, _, state) do
    {:reply, Enum.member?(state.players, name), state}
  end

  def has_player?(logic, name) do
    GenServer.call(logic, {:has_player?, name})
  end

end
