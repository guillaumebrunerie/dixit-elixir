defmodule Dixit.Command do
  @moduledoc """
  Parsing commands.
  """

  def parse(line) do
    case String.split(line) do
      ["NAME", name]   -> {:ok, {:name, name}}
      ["TELL", card]   -> {:ok, {:tell, card}}
      ["SELECT"]       -> {:ok, {:select, nil}}
      ["SELECT", card] -> {:ok, {:select, card}}
      ["VOTE"]         -> {:ok, {:vote, nil}}
      ["VOTE", card]   -> {:ok, {:vote, card}}
      _ -> {:error, :unknown_command}
    end
  end

  def run(command, socket) do
    case command do
      {:name,   name} -> Dixit.GameLogic.run_name(name,   socket)
      {:tell,   card} -> Dixit.GameLogic.run_tell(card,   socket)
      {:select, card} -> Dixit.GameLogic.run_select(card, socket)
      {:vote,   card} -> Dixit.GameLogic.run_vote(card,   socket)
    end
  end

  def format({:players, players}) do
    Enum.reduce(players, "PLAYERS", (fn {k, n}, acc -> "#{acc} #{k} #{n.score}" end))
  end

  def format({:cards, hand}) do
    Enum.reduce(hand, "CARDS", (fn k, acc -> "#{acc} #{k}" end))
  end

  def format({:telling, name}) do
    "TELLING #{name}"
  end

  def format({:selecting, _solution, selecters}) do
    Enum.reduce(selecters, "SELECTING",
      fn {k, n}, acc ->
        case n do
          nil -> "#{acc} #{k}"
          _ -> acc
        end
      end)
  end

  def format({:voting, _solution, _selecters, cards, voters}) do
    card_list = Enum.join(cards, " ")
    voter_list =
      voters
      |> Map.keys
      |> Enum.filter(fn k -> voters[k] == nil end)
      |> Enum.join(" ")
    "VOTING #{card_list} #{voter_list}"
  end

  def format({:next_round, cards, waiting}) do
    cmd_card = fn {card, %{:origin => origin, :votes => votes}} ->
      "CARD #{card} #{origin} #{Enum.join(votes, " ")}"
    end
    Enum.map(cards, cmd_card) ++ ["WAITING #{Enum.join(waiting, " ")}"]
  end
end
