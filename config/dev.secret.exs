use Mix.Config

config :pleroma, Pleroma.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "pleroma",
  password: "pleroma",
  database: "pleroma_dev",
  hostname: "db",
  pool_size: 10


config :pleroma, :instance,
  name: "Pleroma.io",
  email: "h3.poteto@gmail.com",
  limit: 5000,
  registrations_open: true,
  dedupe_media: false


config :pleroma, :fe,
  scope_options_enabled: true
