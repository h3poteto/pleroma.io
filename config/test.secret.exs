use Mix.Config

config :pleroma, Pleroma.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: System.get_env("DB_USER") || "pleroma",
  password: System.get_env("DB_PASSWORD") || "pleroma",
  database: System.get_env("DB_NAME") || "pleroma_test",
  hostname: System.get_env("DB_HOST") || "db",
  pool_size: 10
