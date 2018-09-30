use Mix.Config

config :pleroma, Pleroma.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "pleroma",
  password: "pleroma",
  database: "pleroma_dev",
  hostname: "db",
  pool_size: 10
