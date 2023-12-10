import Config

config :pleroma, Pleroma.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: System.get_env("DB_USER"),
  password: System.get_env("DB_PASSWORD"),
  database: "pleroma_test",
  hostname: System.get_env("DB_HOST"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 50
