defmodule Dixit.Application do
  @moduledoc """
  Main server.
  """

  use Application

  require Logger
  
  @doc """
  Entry point of the server.
  Starts
  - the game logic
  - the supervisor for the players
  - the tasks listening for incoming connections
  """
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: Dixit.GameLogicSupervisor},
      {Dixit.GameRegister, name: Dixit.GameRegister},
      # {Registry, keys: :unique,    name: Dixit.GameRegistry},
      # {Registry, keys: :duplicate, name: Dixit.PlayersRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Dixit.PlayerSupervisor},
      {Dixit.NetworkListener, port: 4020, ws?: true},
      {Dixit.NetworkListener, port: 4000, ws?: false},
    ]

    opts = [strategy: :rest_for_one, name: Dixit.MainSupervisor]
    Supervisor.start_link(children, opts)
  end
end
