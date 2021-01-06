defmodule Dixit.GameLogic do
  @moduledoc """
  Implementation of the game logic.
  """

  use GenServer, restart: :temporary

  require Logger

  @timeout Application.get_env(:dixit, :timeout, 3_600_000)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, opts)
  end

  ## Callbacks

  @impl true
  def init(opts) do
    Logger.info("Hello from a logic")
    # Registry.register(Dixit.GameRegistry, opts[:game], nil)
    deck_size = opts[:deck_size]
    deck = if opts[:random], do: Enum.shuffle(1..deck_size), else: Enum.to_list(1..deck_size)
    initial_state = %{
      players: [],
      scores: %{},
      hands: %{},
      deck: deck,
      phaseT: nil,
#      random: opts[:random]
    }

    {:ok, initial_state, @timeout}
  end

  @impl true
  def handle_call({:get_state}, _, state) do
    {:reply, state, state, @timeout}
  end

  @impl true
  def handle_call({:new_player, name}, _, state) do
    {hand, deck} = Enum.split(state.deck, 6)
    if length(hand) < 6 do
      {:reply, {:error, :no_more_cards}, state, @timeout}
    else
      state =
        state
        |> put_in([:scores, name], 0)
        |> put_in([:hands, name], hand)
        |> put_in([:deck], deck)
        |> update_in([:players], &(&1 ++ [name]))
        |> update_in([:phaseT], &(&1 || %{teller: name, phaseS: nil}))
      {:reply, {:ok, state}, state, @timeout}
    end
  end

  @impl true
  def handle_call({:command, name, command}, _, state) do
    case run(state, name, command) do
      {:ok, new_state, to_broadcast} ->
        {:reply, :ok, new_state, {:continue, {:broadcast, to_broadcast}}}
      {:error, error} ->
        {:reply, {:error, error}, state, @timeout}
    end
  end

  @impl true
  def handle_continue({:broadcast, to_broadcast}, state) do
    if (to_broadcast !== nil) do
      Dixit.GameRegister.broadcast({to_broadcast, state})
    end
    # Always broadcast the new state
    Dixit.GameRegister.broadcast({:state, state})
    {:noreply, state, @timeout}
  end

  @impl true
  def handle_info(:timeout, state) do
    Logger.warn("Game timed out")
    # TODO: close all players
    {:stop, :normal, state}
  end


  ## Nicer interface

  def get_state(logic) do
    GenServer.call(logic, {:get_state})
  end

  def new_player(logic, name) do
    GenServer.call(logic, {:new_player, name})
  end

  def run_command(logic, name, command) do
    GenServer.call(logic, {:command, name, command})
  end


  ## The actual game functions acting on the state
  
  def run(state, player, {:tell, card}) do
    case state.phaseT do
      %{teller: teller, phaseS: nil} ->
        cond do
          teller !== player ->
            {:error, :not_your_turn_to_tell}

          card not in state.hands[player] ->
            {:error, :not_in_your_hand}

          true ->
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
        cond do
          !Map.has_key?(selected, player) ->
            {:error, :not_your_turn_to_select}

          card != nil && card not in state.hands[player] ->
            {:error, :not_in_your_hand}

          true ->
            state = put_in(state.phaseT.phaseS.selected[player], card)
            selected = state.phaseT.phaseS.selected
            if has_nil(selected) do
              {:ok, state, nil}
            else
              # Everyone selected a card
              candidates = Enum.shuffle([answer | Map.values(selected)])
              votes = for p <- state.players, p != teller, into: %{}, do: {p, nil}
              {:ok, put_in(state.phaseT.phaseS.phaseV,
                  %{candidates: candidates,
                    votes: votes,
                    phaseR: nil}), :candidates}
            end
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
      } ->
        cond do
          !Map.has_key?(votes, player) ->
            {:error, :not_your_turn_to_vote}

          card != nil && card not in candidates ->
            {:error, :not_on_the_table}

          true ->
            state = put_in(state.phaseT.phaseS.phaseV.votes[player], card)
            votes = state.phaseT.phaseS.phaseV.votes
            if has_nil(votes) do
              {:ok, state, nil}
            else
              # Everyone has voted, this function computes the origin and the votes of a card
              evaluate = fn card ->
                origin = if card == answer do
                    teller
                  else
                    selected
                    |> Enum.find(fn {_, v} -> v == card end)
                    |> elem(0)
                  end

                votes =
                  votes
                  |> Enum.filter(fn {_, v} -> v == card end)
                  |> Enum.map(&elem(&1,0))

                {card, %{origin: origin, votes: votes}}
              end

              state =
                compute_scores(put_in(state.phaseT.phaseS.phaseV.phaseR,
                      %{results: Map.new(candidates, evaluate),
                        waiting: state.players}))
              {:ok, state, :results}
            end
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
      } ->
        cond do
          player not in waiting ->
            {:error, :already_clicked_next_round}
          true ->
            state = put_in(state.phaseT.phaseS.phaseV.phaseR.waiting, (for p <- waiting, p !== player, do: p))
            state = if state.phaseT.phaseS.phaseV.phaseR.waiting === [] do
              # New round
              next_round(state)
            else
              state
            end
            {:ok, state, nil}
        end
      _ ->
        {:error, :wrong_game_state}
    end
  end

  defp next_in_list(l, v, first \\ nil)

  defp next_in_list([_], _, first) do
    first
  end

  defp next_in_list([p1 | [p2 | rest]], p, first) do
    if (p === p1) do
      p2
    else
      next_in_list([p2 | rest], p, first || p1)
    end
  end

  def has_nil(map) do
    map |> Map.values |> Enum.member?(nil)
  end

  def next_round(state) do
    teller = state.phaseT.teller
    answer = state.phaseT.phaseS.answer
    selected = state.phaseT.phaseS.selected
    new_hands = state.hands |> Enum.reduce(
      {:ok, state.deck, %{}},
      fn {player, hand}, {:ok, [card | deck], new_hands} -> (
          new_hand = [card | List.delete(hand, (if player === teller, do: answer, else: selected[player]))]
          {:ok, deck, Map.put(new_hands, player, new_hand)})

        _ , _ ->
          Logger.info("Exhausted deck!")
          :exhausted_deck
      end)
    case new_hands do
      {:ok, deck, hands} ->
        %{players: state.players,
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
    teller = state.phaseT.teller
    answer = state.phaseT.phaseS.answer
    selected = state.phaseT.phaseS.selected
    results = state.phaseT.phaseS.phaseV.phaseR.results
    votes_for_teller = length(results[answer].votes)
    well_done = votes_for_teller > 0 && votes_for_teller < length(state.players) - 1
    scores =
      Map.new(state.scores, fn {player, score} -> {
        player,
        score +
          if(well_done && (player === teller || player in results[answer].votes),
              do: 3, else: 0) +
          if(!well_done && player !== teller,
              do: 2, else: 0) +
          if(player !== teller,
              do: length(results[selected[player]].votes), else: 0)
        }
      end)

    %{state | scores: scores}
  end
end
