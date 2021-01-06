defmodule Dixit.Command do
  @moduledoc """
  Parsing commands.
  """

  @doc """
  Parse the given message into a command.

  ## Examples

    iex> parse("JOINGAME 42 Guillaume")
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

  # When a player joins (or rejoins), the full state is sent to them:
  #   format_state(state, player, true)
  # Whenever the state changes, the partial state is sent to all players:
  #   format_state(state, player)
  def format_state(state, player, full? \\ false) do
    case state.phaseT do
      # The game is finished
      nil ->
        format_gameover(state.scores)

      # We are in TELLING phase or later
      %{teller: teller, phaseS: phaseS} ->
        if(full?, do: format({:players, state, nil}), else: []) ++
          if(full?, do: format_hand(state.hands[player]), else: []) ++
          case phaseS do
            # We are in TELLING phase
            nil ->
              if(!full?, do: format_hand(state.hands[player]), else: []) ++
                ["TELLING #{teller}"]

            # We are in SELECTING phase or later
            %{answer: answer, selected: selected, phaseV: phaseV} ->
              if(full?, do: ["TELLER #{teller}"], else: []) ++
                if(full? && player == teller, do: ["TOLD #{answer}"], else: []) ++
                if(full? && player != teller && selected[player],
                  do: ["SELECTED #{selected[player]}"],
                  else: []
                ) ++
                case phaseV do
                  # We are in SELECTING phase
                  nil ->
                    ["SELECTING #{all_nil(selected)}"]

                  # We are in VOTING phase or later
                  %{candidates: candidates, votes: votes, phaseR: phaseR} ->
                    if(full? && player != teller && votes[player],
                      do: ["VOTED #{votes[player]}"],
                      else: []
                    ) ++
                      case phaseR do
                        # We are in VOTING phase
                        nil ->
                          if(full?, do: ["CANDIDATES #{Enum.join(candidates, " ")}"], else: []) ++
                            ["VOTING #{all_nil(votes)}"]

                        # ["VOTING #{Enum.join(candidates, " ")} #{all_nil(votes)}"]

                        # We are in RESULTS phase
                        %{results: _results, waiting: waiting} ->
                          if(full?, do: format({:results, state, nil}), else: []) ++
                            if(full? && !(player in waiting), do: ["CLICKEDNEXTROUND"], else: []) ++
                            ["WAITING #{Enum.join(waiting, " ")}"]
                      end
                end
          end
    end
  end

  def all_nil(map) do
    map
    |> Map.keys()
    |> Enum.filter(fn k -> map[k] == nil end)
    |> Enum.join(" ")
  end

  @doc """

    iex> format_gameover(%{"A" => 6, "B" => 2, "C" => 4, "D" => 1})
    ["GAMEFINISHED A 6 C 4 B 2 D 1"]

    iex> format_gameover(%{"A" => 5, "B" => 9, "C" => 2, "D" => 3, "E" => 7})
    ["GAMEFINISHED B 9 E 7 A 5 D 3 C 2"]
  """
  def format_gameover(scores) do
    fmt_scores = fn {p, s} -> "#{p} #{s}" end
    cmp_scores = fn {_, s}, {_, s2} -> s >= s2 end
    ["GAMEFINISHED #{scores |> Enum.sort(cmp_scores) |> Enum.map(fmt_scores) |> Enum.join(" ")}"]
  end

  @doc """
    iex> format_hand([1, 3, 42, 2])
    ["CARDS 1 3 42 2"]
  """
  def format_hand(hand) do
    ["CARDS #{hand |> Enum.map(&to_string/1) |> Enum.join(" ")}"]
  end

  @doc """
    iex> format({:players, %{players: ["A", "C", "B"], scores: %{"C" => 42, "B" => 2, "A" => 12}}, nil})
    ["PLAYERS A 12 C 42 B 2"]
  """
  def format({:players, state, _}) do
    fmt_scores = fn p -> "#{p} #{state.scores[p]}" end
    ["PLAYERS #{state.players |> Enum.map(fmt_scores) |> Enum.join(" ")}"]
  end

  def format({:candidates, state, _}) do
    candidates = state.phaseT.phaseS.phaseV.candidates
    ["CANDIDATES #{Enum.join(candidates, " ")}"]
  end

  def format({:results, state, _}) do
    candidates = state.phaseT.phaseS.phaseV.candidates
    results = state.phaseT.phaseS.phaseV.phaseR.results

    cmd_card = fn card ->
      %{origin: origin, votes: votes} = results[card]
      "#{card} #{origin} #{length(votes)} #{Enum.join(votes, " ")}"
    end

    format({:players, state, nil}) ++
      ["RESULTS #{candidates |> Enum.map(cmd_card) |> Enum.join(" ")}"]
  end

  def format({:state, state, player}) do
    format_state(state, player, false)
  end
end
