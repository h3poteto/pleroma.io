import Config

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
  remote_post_retention_days: 180

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

config :pleroma, :shout, enabled: false

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

config :logger,
  backends: [:console]

# MetricsExport will not read env when runtime
# So I want to use runtime.exs instead of Mix.Config, but it is not supported, so I'm waiting.
# config :prometheus, Pleroma.Web.Endpoint.MetricsExporter,
#   enabled: true,
#   auth: {:basic, System.fetch_env!("METRICS_USER"), System.fetch_env!("METRICS_PASSWORD")},
#   ip_whitelist: [],
#   path: "/api/pleroma/app_metrics",
#   format: :text

if File.exists?("/opt/pleromaio/prod.secret.exs") do
  import_config "/opt/pleromaio/prod.secret.exs"
end
