import Config

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

config :pleroma, :instance,
  name: "Pleroma.io",
  email: "h3.poteto@gmail.com",
  limit: 5000,
  registrations_open: false,
  invites_enabled: true,
  dynamic_configuration: false,
  remote_post_retention_days: 365

config :pleroma, :shout, enabled: false

config :pleroma, :frontend_configurations,
  pleroma_fe: %{
    showInstanceSpecificPanel: true,
    scopeOptionsEnabled: false
  }
