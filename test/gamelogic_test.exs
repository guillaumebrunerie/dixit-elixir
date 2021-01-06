defmodule Dixit.GameLogicTest do
  use ExUnit.Case

  import Dixit.GameLogic
  
  setup do
    logic = start_supervised!({Dixit.GameLogic, name: Dixit.GameLogicTest, random: false, deck_size: 42})
    %{logic: logic}
  end
  
  test "Main flow", %{logic: logic} do
    handG = [1, 2, 3, 4, 5, 6]
    state1 = %{
      hands: %{"G" => handG},
      phaseT: %{phaseS: nil, teller: "G"},
      players: ["G"],
      scores: %{"G" => 0},
      deck: Enum.to_list(7..42)
    }

    handS = [7, 8, 9, 10, 11, 12]
    state2 = %{
      hands: %{"G" => handG, "S" => handS},
      phaseT: %{phaseS: nil, teller: "G"},
      players: ["G", "S"],
      scores: %{"G" => 0, "S" => 0},
      deck: Enum.to_list(13..42)
    }

    handM = [13, 14, 15, 16, 17, 18]
    state3 = %{
      hands: %{"G" => handG, "S" => handS, "M" => handM},
      phaseT: %{phaseS: nil, teller: "G"},
      players: ["G", "S", "M"],
      scores: %{"G" => 0, "S" => 0, "M" => 0},
      deck: Enum.to_list(19..42)
    }
    
    assert {:ok, ^state1} = new_player(logic, "G")
    assert {:ok, ^state2} = new_player(logic, "S")
    assert {:ok, ^state3} = new_player(logic, "M")
    assert {:error, :not_your_turn_to_tell} = run_command(logic, "S", {:tell, 1})
    assert {:error, :wrong_game_state}      = run_command(logic, "G", {:select, 1})

    state4 = put_in(state3.phaseT.phaseS, %{answer: 3, phaseV: nil, selected: %{"S" => nil, "M" => nil}})

    assert :ok = run_command(logic, "G", {:tell, 3})
    assert state4 == get_state(logic)

    state5 = state4 |> put_in([:phaseT, :phaseS, :selected, "S"], 7)
    
    assert :ok = run_command(logic, "S", {:select, 7})
    assert state5 == get_state(logic)

    # state6 = state5
    # |> put_in([:phaseT, :phaseS, :selected, "M"], 13)
    # |> put_in([:phaseT, :phaseS, :phaseV], %{candidates: [7, 3, 13], phaseR: nil, votes: %{"S" => nil, "M" => nil}})
    
    assert :ok = run_command(logic, "M", {:select, 13})

    assert {:error, :not_on_the_table} =
      run_command(logic, "S", {:vote, 1})
    assert :ok =
      run_command(logic, "S", {:vote, 3})
    assert :ok =
      run_command(logic, "M", {:vote, 3})
    assert :ok =
      run_command(logic, "G", {:nextround})
    assert :ok =
      run_command(logic, "M", {:nextround})
    assert :ok =
      run_command(logic, "S", {:nextround})
    state = get_state(logic)
    assert state.scores["G"] == 0
    assert state.scores["S"] == 2
    assert state.scores["M"] == 2
  end

  # setup do
  #   Application.stop(:dixit)
  #   :ok = Application.start(:dixit)
  # end

  # setup do
  #   opts = [:binary, packet: :line, active: false]
  #   {:ok, socket1} = :gen_tcp.connect('localhost', 4010, opts)
  #   {:ok, socket2} = :gen_tcp.connect('localhost', 4010, opts)
  #   %{socket1: socket1, socket2: socket2}
  # end
  
  # test "server interaction", %{socket1: socket1, socket2: socket2} do
  #   snd(socket1, "NAME Guillaume")
  #   snd(socket2, "NAME Sylvain")
  #   snd(socket1, "TELL 1")
  #   snd(socket2, "SELECT 2")
  #   snd(socket2, "VOTE 3")
  #   snd(socket1, "NEXTROUND")
  # end

  # defp snd(socket, command) do
  #   :ok = :gen_tcp.send(socket, command <> "\r\n")
  # end

  # defp rcv(socket) do
  #   {:ok, data} = :gen_tcp.recv(socket, 0)
  #   String.trim(data)
  # end

end
