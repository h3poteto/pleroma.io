import Config

if config_env() == :prod do
  # Do not use SSL in phoenix.
  # Because SSL set up in ALB with ACM.
  config :pleroma, Pleroma.Web.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: 4000],
    url: [host: "pleroma.io", scheme: "https", port: 443],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE")

  config :pleroma, Pleroma.Uploaders.S3,
    bucket: System.fetch_env!("S3_BUCKET"),
    truncated_namespace: ""

  config :web_push_encryption, :vapid_details,
    subject: "mailto:h3.poteto@gmail.com",
    public_key: System.fetch_env!("WEB_PUSH_PUBLIC_KEY"),
    private_key: System.fetch_env!("WEB_PUSH_PRIVATE_KEY")

  config :rollbax,
    access_token: System.fetch_env!("ROLLBAR_ACCESS_TOKEN"),
    environment: "production",
    enable_crash_reports: true,
    enabled: true
end

config :pleroma, Pleroma.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: System.fetch_env!("DB_USER"),
  password: System.fetch_env!("DB_PASSWORD"),
  database: System.fetch_env!("DB_NAME"),
  hostname: System.fetch_env!("DB_HOST"),
  pool_size: 10,
  timeout: 60_000
