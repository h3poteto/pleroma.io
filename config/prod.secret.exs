use Mix.Config

# Do not use SSL in phoenix.
# Because SSL set up in ALB with ACM.
config :pleroma, Pleroma.Web.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  url: [host: "pleroma.io", scheme: "https", port: 443],
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
  invites_enabled: true,
  dynamic_configuration: false,
  remote_post_retention_days: 365

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
  truncated_namespace: ""

config :ex_aws,
  # We have to set dummy profile to use web identity adapter.
  # So this profile does not exist and don't prepare it.
  secret_access_key: [{:awscli, "profile_name", 30}],
  access_key_id: [{:awscli, "profile_name", 30}],
  awscli_auth_adapter: ExAws.STS.AuthCache.AssumeRoleWebIdentityAdapter

config :ex_aws, :s3,
  # We have to set dummy profile to use web identity adapter.
  # So this profile does not exist and don't prepare it.
  secret_access_key: [{:awscli, "profile_name", 30}],
  access_key_id: [{:awscli, "profile_name", 30}],
  awscli_auth_adapter: ExAws.STS.AuthCache.AssumeRoleWebIdentityAdapter,
  region: "ap-northeast-1",
  scheme: "https://"

config :pleroma, Pleroma.Upload,
  uploader: Pleroma.Uploaders.S3,
  base_url: "https://media.pleroma.io"

config :pleroma, :chat, enabled: false

config :pleroma, :frontend_configurations,
  pleroma_fe: %{
    showInstanceSpecificPanel: true,
    scopeOptionsEnabled: false
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
  backends: [:console]

config :rollbax,
  access_token: System.get_env("ROLLBAR_ACCESS_TOKEN"),
  environment: "production",
  enable_crash_reports: true,
  enabled: true

# MetricsExport will not read env when runtime
# So I want to use runtime.exs instead of Mix.Config, but it is not supported, so I'm waiting.
# config :prometheus, Pleroma.Web.Endpoint.MetricsExporter,
#   enabled: true,
#   auth: {:basic, System.fetch_env!("METRICS_USER"), System.fetch_env!("METRICS_PASSWORD")},
#   ip_whitelist: [],
#   path: "/api/pleroma/app_metrics",
#   format: :text
