defmodule Dixit.Command do
  @moduledoc """
  Parsing commands.
  """

  def parse(line) do
    case String.split(line) do
      ["NAME", name]   -> {:ok, {:name, name}}
      ["TELL", card]   -> {:ok, {:tell, String.to_integer(card)}}
      ["SELECT"]       -> {:ok, {:select, nil}}
      ["SELECT", card] -> {:ok, {:select, String.to_integer(card)}}
      ["VOTE"]         -> {:ok, {:vote, nil}}
      ["VOTE", card]   -> {:ok, {:vote, String.to_integer(card)}}
      ["NEXTROUND"]    -> {:ok, {:nextround}}
      _ -> {:error, :unknown_command}
    end
  end

  def run(command, logic \\ Dixit.GameLogic) do
    case command do
      {:name,   name} -> Dixit.GameLogic.run_name(name, logic)
      {:tell,   card} -> Dixit.GameLogic.run_tell(card, logic)
      {:select, card} -> Dixit.GameLogic.run_select(card, logic)
      {:vote,   card} -> Dixit.GameLogic.run_vote(card, logic)
      {:nextround}    -> Dixit.GameLogic.run_nextround(logic)
    end
  end

  def format_state(state) do
    case state.phaseT do
      %{teller: teller,
        phaseS: nil
      } -> [format({:players, state.players, state.scores}),
           "TELLING #{teller}"]

      %{teller: teller,
        phaseS: %{
          selected: selected,
          phaseV: nil
        }
      } -> ["TELLER #{teller}",
           "SELECTING #{all_nil(selected)}"]

      %{teller: teller,
        phaseS: %{
          phaseV: %{
            candidates: candidates,
            votes: votes,
            phaseR: nil
          }
        }
      } -> ["TELLER #{teller}",
           "VOTING #{Enum.join(candidates, " ")} #{all_nil(votes)}"]

      %{teller: teller,
        phaseS: %{
          answer: answer,
          selected: selected,
          phaseV: %{
            phaseR: %{
              results: results,
              waiting: waiting
            }
          }
        }
      } ->
        cmd_card = fn {origin, votes} ->
          card = if origin === teller, do: answer, else: selected[origin]
          "#{card} #{origin} #{length votes} #{Enum.join(votes, " ")}"
        end
        ["TELLER #{teller}",
         "RESULTS #{results |> Enum.map(cmd_card) |> Enum.join(" ")}",
         format({:players, state.players, state.scores}),
         "WAITING #{Enum.join(waiting, " ")}"]
    end
          
  end

  def all_nil(map) do
    map
    |> Map.keys
    |> Enum.filter(fn k -> map[k] == nil end)
    |> Enum.join(" ")
  end
  
  def format({:players, players, scores}) do
    fmt_scores = fn p ->
      "#{p} #{scores[p]}"
    end
    "PLAYERS #{players |> Enum.map(fmt_scores) |> Enum.join(" ")}"
  end

  def format({:cards, hand}) do
    Enum.reduce(hand, "CARDS", (fn k, acc -> "#{acc} #{k}" end))
  end

  # def format({:telling, name}) do
  #   "TELLING #{name}"
  # end

  # def format({:selecting, _solution, selecters}) do
  #   Enum.reduce(selecters, "SELECTING",
  #     fn {k, n}, acc ->
  #       case n do
  #         nil -> "#{acc} #{k}"
  #         _ -> acc
  #       end
  #     end)
  # end

  # def format({:voting, _solution, _selecters, cards, voters}) do
  #   card_list = Enum.join(cards, " ")
  #   voter_list =
  #     voters
  #     |> Map.keys
  #     |> Enum.filter(fn k -> voters[k] == nil end)
  #     |> Enum.join(" ")
  #   "VOTING #{card_list} #{voter_list}"
  # end
end
