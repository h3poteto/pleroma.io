use Mix.Config

# Do not use SSL in phoenix.
# Because SSL set up in ALB with ACM.
config :pleroma, Pleroma.Web.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  url: [host: "pleroma.io", scheme: "https", port: 443],
  server: true,
  secret_key_base: System.get_env("SECRET_KEY_BASE")

config :pleroma, :media_proxy,
  enabled: true,
  redirect_on_failure: true

# base_url: "https://cache.pleroma.io"

config :pleroma, :instance,
  name: "Pleroma.io",
  email: "h3.poteto@gmail.com",
  notify_email: "h3.poteto@gmail.com",
  limit: 5000,
  registrations_open: false,
  dynamic_configuration: false

config :pleroma, Pleroma.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: System.get_env("DB_USER"),
  password: System.get_env("DB_PASSWORD"),
  database: System.get_env("DB_NAME"),
  hostname: System.get_env("DB_HOST"),
  pool_size: 10,
  timeout: 60_000

config :pleroma, Pleroma.Uploaders.S3,
  bucket: System.get_env("S3_BUCKET"),
  # Using CloudFront which name is same as s3 bucket name.
  # So if we set public endpoint, the URL is `https://media.pleroma.io/media.pleroma.io/filename.png`.
  public_endpoint: "https://"

config :ex_aws,
  # We have to set dummy profile to use web identity adapter.
  # So this profile does not exist and don't prepare it.
  secret_access_key: [{:awscli, "profile_name", 30}],
  access_key_id: [{:awscli, "profile_name", 30}],
  awscli_auth_adapter: ExAws.STS.AuthCache.AssumeRoleWebIdentityAdapter

config :ex_aws, :s3,
  region: "ap-northeast-1",
  scheme: "https://"

config :pleroma, Pleroma.Upload, uploader: Pleroma.Uploaders.S3

config :pleroma, :chat, enabled: false

config :pleroma, :frontend_configurations,
  pleroma_fe: %{
    scope_options_enabled: true
  }

config :pleroma, :suggestions,
  enabled: true,
  third_party_engine:
    "http://vinayaka.distsn.org/cgi-bin/vinayaka-user-match-suggestions-api.cgi?{{host}}+{{user}}",
  timeout: 300_000,
  limit: 23,
  web: "https://vinayaka.distsn.org/?{{host}}+{{user}}"

config :web_push_encryption, :vapid_details,
  subject: "mailto:h3.poteto@gmail.com",
  public_key: System.get_env("WEB_PUSH_PUBLIC_KEY"),
  private_key: System.get_env("WEB_PUSH_PRIVATE_KEY")

config :logger,
  backends: [:console, Sentry.LoggerBackend]

config :sentry,
  dsn: System.get_env("SENTRY_DSN"),
  environment_name: Mix.env(),
  included_environments: [:prod],
  enable_source_code_context: true,
  root_source_code_path: File.cwd!(),
  filter: Pleroma.SentryEventFilter
