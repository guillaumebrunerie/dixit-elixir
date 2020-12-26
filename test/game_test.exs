defmodule Dixit.GameLogicTest do
  use ExUnit.Case, async: true

  setup do
    server = start_supervised!(Dixit.GameLogic)
    %{registry: server}
  end
  
  test "first", %{registry: registry} do
    assert Dixit.GameLogic.run_name("Guillaume", nil) == 
  end
end
