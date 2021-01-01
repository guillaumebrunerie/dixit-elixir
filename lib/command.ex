defmodule Dixit.Command do
  @moduledoc """
  Parsing commands.
  """

  @doc ~S"""
  Parse the given message into a command.

  ## Examples

    iex> Dixit.Command.parse("JOINGAME 42 Guillaume\r\n")
    {:ok, {:join_game, "42", "Guillaume"}}
  """
  def parse(line) do
    case String.split(line) do
      ["JOINGAME", game, name] -> {:ok, {:join_game, game, name}}
      ["NAME", name]           -> {:ok, {:join_game, "default", name}}
      ["TELL", card]           -> {:ok, {:tell, String.to_integer(card)}}
      ["SELECT", card]         -> {:ok, {:select, String.to_integer(card)}}
      ["SELECT"]               -> {:ok, {:select, nil}}
      ["VOTE", card]           -> {:ok, {:vote, String.to_integer(card)}}
      ["VOTE"]                 -> {:ok, {:vote, nil}}
      ["NEXTROUND"]            -> {:ok, {:nextround}}
      ["CRASH"]                -> {:ok, {:crash}}
      _ -> {:error, :unknown_command}
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
      } -> [format({:players, state.players, state.scores}),
           "TELLER #{teller}",
           "SELECTING #{all_nil(selected)}"]

      %{teller: teller,
        phaseS: %{
          phaseV: %{
            candidates: candidates,
            votes: votes,
            phaseR: nil
          }
        }
      } -> [format({:players, state.players, state.scores}),
           "TELLER #{teller}",
           "VOTING #{Enum.join(candidates, " ")} #{all_nil(votes)}"]

      %{teller: teller,
        phaseS: %{
          phaseV: %{
            candidates: candidates,
            phaseR: %{
              results: results,
              waiting: waiting
            }
          }
        }
      } ->
        cmd_card = fn card ->
          %{origin: origin, votes: votes} = results[card]
          "#{card} #{origin} #{length votes} #{Enum.join(votes, " ")}"
        end
        ["TELLER #{teller}",
         "RESULTS #{candidates |> Enum.map(cmd_card) |> Enum.join(" ")}",
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
end
