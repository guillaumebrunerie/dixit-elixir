use Mix.Config

config :logger, :console,
  format: "$time $metadata[$level] $levelpad$message\n",
  metadata: [:pid]

# config :dixit, timeout: 3_600_000
