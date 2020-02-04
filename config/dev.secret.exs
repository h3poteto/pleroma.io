use Mix.Config

config :pleroma, Pleroma.Web.Endpoint,
  http: [
    ip: {0, 0, 0, 0},
    port: 4000,
    protocol_options: [max_request_line_length: 8192, max_header_value_length: 8192]
  ],
  protocol: "http",
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [],
  secure_cookie_flag: false

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
  dynamic_configuration: false

config :pleroma, :chat, enabled: false

config :pleroma, :fe, scope_options_enabled: true
