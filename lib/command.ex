defmodule Dixit.Command do
  @moduledoc """
  Parsing commands.
  """

  @doc ~S"""
  Parse the given message into a command.

  ## Examples

    iex> parse("JOINGAME 42 Guillaume\r\n")
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
      nil -> [format_gameover(state.scores)]

      %{teller: teller,
        phaseS: nil
      } -> [format_players(state.players, state.scores),
           "TELLING #{teller}"]

      %{teller: teller,
        phaseS: %{
          selected: selected,
          phaseV: nil
        }
      } -> [format_players(state.players, state.scores),
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
      } -> [format_players(state.players, state.scores),
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
         format_players(state.players, state.scores),
         "WAITING #{Enum.join(waiting, " ")}"]
    end
          
  end

  def all_nil(map) do
    map
    |> Map.keys
    |> Enum.filter(fn k -> map[k] == nil end)
    |> Enum.join(" ")
  end

  @doc """

    iex> format_gameover(%{"A" => 6, "B" => 2, "C" => 4, "D" => 1})
    "GAMEFINISHED A 6 C 4 B 2 D 1"

    iex> format_gameover(%{"A" => 5, "B" => 9, "C" => 2, "D" => 3, "E" => 7})
    "GAMEFINISHED B 9 E 7 A 5 D 3 C 2"
  """
  def format_gameover(scores) do
    fmt_scores = fn {p, s} -> "#{p} #{s}" end
    cmp_scores = fn ({_, s}, {_, s2}) -> s >= s2 end
    "GAMEFINISHED #{scores |> Enum.sort(cmp_scores) |> Enum.map(fmt_scores) |> Enum.join(" ")}"
  end

  @doc """
    iex> format_players(["A", "C", "B"], %{"C" => 42, "B" => 2, "A" => 12})
    "PLAYERS A 12 C 42 B 2"
  """
  def format_players(players, scores) do
    fmt_scores = fn p -> "#{p} #{scores[p]}" end
    "PLAYERS #{players |> Enum.map(fmt_scores) |> Enum.join(" ")}"
  end

  @doc """
    iex> format_hand([1, 3, 42, 2])
    "CARDS 1 3 42 2"
  """
  def format_hand(hand) do
    "CARDS #{hand |> Enum.map(&to_string/1) |> Enum.join(" ")}"
  end
end
