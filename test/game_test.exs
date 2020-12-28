defmodule Dixit.GameLogicTest do
  use ExUnit.Case

  # setup do
  #   logic = start_supervised!({Dixit.GameLogic, name: Dixit.GameLogic, random: false})
  #   :ok #%{logic: logic}
  # end

  test "Duplicate name" do
    Dixit.GameLogic.run_name("Guillaume")
    assert 1 == Dixit.GameLogic.run_name("Guillaume")
  end
  
  test "Main flow" do
    assert {:ok, _, _} = Dixit.GameLogic.run_name("Guillaume")
    assert {:ok, _, _} = Dixit.GameLogic.run_name("Sylvain")
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
  #   String.trim_trailing(data)
  # end

end
