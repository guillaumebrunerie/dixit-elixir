defmodule Dixit.CommandTest do
  use ExUnit.Case

  import Dixit.Command
  import Dixit.GameLogic

  doctest Dixit.Command
  
  setup do
    logic = start_supervised!({Dixit.GameLogic, name: Dixit.GameLogicTest, random: false, deck_size: 42})
    %{logic: logic}
  end

  test "format_state", %{logic: logic} do
    new_player(logic, "G")
    new_player(logic, "S")
    new_player(logic, "M")
    state = get_state(logic)

    assert format_state(state, "G", false) ==
      [ "CARDS 1 2 3 4 5 6", "TELLING G"]
    assert format_state(state, "G", true) ==
      ["PLAYERS G 0 S 0 M 0", "CARDS 1 2 3 4 5 6", "TELLING G"]
    assert format_state(state, "S", false) ==
      ["CARDS 7 8 9 10 11 12", "TELLING G"]
    assert format_state(state, "S", true) ==
      ["PLAYERS G 0 S 0 M 0", "CARDS 7 8 9 10 11 12", "TELLING G"]

    run_command(logic, "G", {:tell, 3})
    state = get_state(logic)

    assert format_state(state, "G", false) ==
      ["SELECTING M S"]
    assert format_state(state, "G", true) ==
      ["PLAYERS G 0 S 0 M 0", "CARDS 1 2 3 4 5 6", "TELLER G", "TOLD 3", "SELECTING M S"]
    assert format_state(state, "M", false) ==
      ["SELECTING M S"]
    assert format_state(state, "M", true) ==
      ["PLAYERS G 0 S 0 M 0", "CARDS 13 14 15 16 17 18", "TELLER G", "SELECTING M S"]

    run_command(logic, "S", {:select, 10})
    state = get_state(logic)

    assert format_state(state, "G", false) ==
      ["SELECTING M"]
    assert format_state(state, "G", true) ==
      ["PLAYERS G 0 S 0 M 0", "CARDS 1 2 3 4 5 6", "TELLER G", "TOLD 3", "SELECTING M"]
    assert format_state(state, "M", false) ==
      ["SELECTING M"]
    assert format_state(state, "M", true) ==
      ["PLAYERS G 0 S 0 M 0", "CARDS 13 14 15 16 17 18", "TELLER G", "SELECTING M"]
    assert format_state(state, "S", false) ==
      ["SELECTING M"]
    assert format_state(state, "S", true) ==
      ["PLAYERS G 0 S 0 M 0", "CARDS 7 8 9 10 11 12", "TELLER G", "SELECTED 10", "SELECTING M"]

    run_command(logic, "M", {:select, 15})
    state = get_state(logic)

    assert format_state(state, "G", false) ==
      ["VOTING M S"]
    assert ["PLAYERS G 0 S 0 M 0", "CARDS 1 2 3 4 5 6", "TELLER G", "TOLD 3", ("CANDIDATES " <> _) = candidates, "VOTING M S"] = format_state(state, "G", true)
    assert format_state(state, "M", false) ==
      ["VOTING M S"]
    assert format_state(state, "M", true) ==
      ["PLAYERS G 0 S 0 M 0", "CARDS 13 14 15 16 17 18", "TELLER G", "SELECTED 15", candidates,
       "VOTING M S"]
    assert format_state(state, "S", false) ==
      ["VOTING M S"]
    assert format_state(state, "S", true) ==
      ["PLAYERS G 0 S 0 M 0", "CARDS 7 8 9 10 11 12", "TELLER G", "SELECTED 10", candidates,
       "VOTING M S"]

    run_command(logic, "M", {:vote, 10})
    state = get_state(logic)

    assert format_state(state, "G", false) ==
      ["VOTING S"]
    assert format_state(state, "G", true) ==
      ["PLAYERS G 0 S 0 M 0", "CARDS 1 2 3 4 5 6", "TELLER G", "TOLD 3", candidates, "VOTING S"]
    assert format_state(state, "M", false) ==
      ["VOTING S"]
    assert format_state(state, "M", true) ==
      ["PLAYERS G 0 S 0 M 0", "CARDS 13 14 15 16 17 18", "TELLER G", "SELECTED 15", "VOTED 10", candidates,
       "VOTING S"]
    assert format_state(state, "S", false) ==
      ["VOTING S"]
    assert format_state(state, "S", true) ==
      ["PLAYERS G 0 S 0 M 0", "CARDS 7 8 9 10 11 12", "TELLER G", "SELECTED 10", candidates,
       "VOTING S"]

    run_command(logic, "M", {:vote, nil})
    state = get_state(logic)

    assert format_state(state, "G", false) ==
      ["VOTING M S"]
    assert format_state(state, "G", true) ==
      ["PLAYERS G 0 S 0 M 0", "CARDS 1 2 3 4 5 6", "TELLER G", "TOLD 3", candidates, "VOTING M S"]
    assert format_state(state, "M", false) ==
      ["VOTING M S"]
    assert format_state(state, "M", true) ==
      ["PLAYERS G 0 S 0 M 0", "CARDS 13 14 15 16 17 18", "TELLER G", "SELECTED 15", candidates,
       "VOTING M S"]
    assert format_state(state, "S", false) ==
      ["VOTING M S"]
    assert format_state(state, "S", true) ==
      ["PLAYERS G 0 S 0 M 0", "CARDS 7 8 9 10 11 12", "TELLER G", "SELECTED 10", candidates,
       "VOTING M S"]

    run_command(logic, "M", {:vote, 3})
    run_command(logic, "S", {:vote, 3})
    state = get_state(logic)

    assert format_state(state, "G", false) ==
      ["WAITING G S M"]
    assert ["PLAYERS G 0 S 2 M 2", "CARDS 1 2 3 4 5 6", "TELLER G", "TOLD 3",
       ("RESULTS " <> _) = results, "WAITING G S M"] = format_state(state, "G", true)
    assert format_state(state, "M", false) ==
      ["WAITING G S M"]
    assert format_state(state, "M", true) ==
      ["PLAYERS G 0 S 2 M 2", "CARDS 13 14 15 16 17 18", "TELLER G", "SELECTED 15",
       "VOTED 3", results, "WAITING G S M"]
    assert format_state(state, "S", false) ==
      ["WAITING G S M"]
    assert format_state(state, "S", true) ==
      ["PLAYERS G 0 S 2 M 2", "CARDS 7 8 9 10 11 12", "TELLER G", "SELECTED 10",
       "VOTED 3", results, "WAITING G S M"]

    run_command(logic, "G", {:nextround})
    state = get_state(logic)

    assert format_state(state, "G", false) ==
      ["WAITING S M"]
    assert format_state(state, "G", true) ==
      ["PLAYERS G 0 S 2 M 2", "CARDS 1 2 3 4 5 6", "TELLER G", "TOLD 3", results,
       "CLICKEDNEXTROUND", "WAITING S M"]
    assert format_state(state, "M", false) ==
      ["WAITING S M"]
    assert format_state(state, "M", true) ==
      ["PLAYERS G 0 S 2 M 2", "CARDS 13 14 15 16 17 18", "TELLER G", "SELECTED 15", "VOTED 3",
       results, "WAITING S M"]
    assert format_state(state, "S", false) ==
      ["WAITING S M"]
    assert format_state(state, "S", true) ==
      ["PLAYERS G 0 S 2 M 2", "CARDS 7 8 9 10 11 12", "TELLER G", "SELECTED 10", "VOTED 3",
       results, "WAITING S M"]

    run_command(logic, "S", {:nextround})
    state = get_state(logic)

    assert format_state(state, "G", false) ==
      ["WAITING M"]
    assert format_state(state, "G", true) ==
      ["PLAYERS G 0 S 2 M 2", "CARDS 1 2 3 4 5 6", "TELLER G", "TOLD 3", results,
       "CLICKEDNEXTROUND", "WAITING M"]
    assert format_state(state, "M", false) ==
      ["WAITING M"]
    assert format_state(state, "M", true) ==
      ["PLAYERS G 0 S 2 M 2", "CARDS 13 14 15 16 17 18", "TELLER G", "SELECTED 15", "VOTED 3",
       results, "WAITING M"]
    assert format_state(state, "S", false) ==
      ["WAITING M"]
    assert format_state(state, "S", true) ==
      ["PLAYERS G 0 S 2 M 2", "CARDS 7 8 9 10 11 12", "TELLER G", "SELECTED 10", "VOTED 3", results,
       "CLICKEDNEXTROUND", "WAITING M"]

    run_command(logic, "M", {:nextround})
    state = get_state(logic)

    assert format_state(state, "G", false) ==
      ["CARDS 19 1 2 4 5 6", "TELLING S"]
    assert format_state(state, "G", true) ==
      ["PLAYERS G 0 S 2 M 2", "CARDS 19 1 2 4 5 6", "TELLING S"]
    assert format_state(state, "S", false) ==
      ["CARDS 21 7 8 9 11 12", "TELLING S"]
    assert format_state(state, "S", true) ==
      ["PLAYERS G 0 S 2 M 2", "CARDS 21 7 8 9 11 12", "TELLING S"]
    assert format_state(state, "M", false) ==
      ["CARDS 20 13 14 16 17 18", "TELLING S"]
    assert format_state(state, "M", true) ==
      ["PLAYERS G 0 S 2 M 2", "CARDS 20 13 14 16 17 18", "TELLING S"]
  end
end
