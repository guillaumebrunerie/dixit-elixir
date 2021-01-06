defmodule Dixit.MixProject do
  use Mix.Project

  def project do
    [
      app: :dixit,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      mod: {Dixit.Application, []}
      # dialyzer: [flags: [:overspecs]]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Dixit.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
    ]
  end
end
