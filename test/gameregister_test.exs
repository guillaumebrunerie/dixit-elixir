defmodule Dixit.GameRegisterTest do
  use ExUnit.Case

  import Dixit.GameRegister
  
  test "New player" do
    assert {:ok, _, _} = run({:join_game, "default", "G"})
    # Task.run(fn -> run({:name, "S"}))
    # assert {:ok, _, _} = run({:name, "G"})
  end
end
