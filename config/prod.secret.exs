use Mix.Config

# Do not use SSL in phoenix.
# Because SSL set up in ALB with ACM.
config :pleroma, Pleroma.Web.Endpoint,
  http: [port: 4000],
  url: [host: "pleroma.io", scheme: "https", port: 443],
  server: true,
  secret_key_base: System.get_env("SECRET_KEY_BASE")

config :pleroma, :media_proxy,
  enabled: true,
  redirect_on_failure: true
  #base_url: "https://cache.pleroma.io"

config :pleroma, :instance,
  name: "Pleroma.io",
  email: "h3.poteto@gmail.com",
  limit: 5000,
  registrations_open: true,
  dedupe_media: false

config :pleroma, Pleroma.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: System.get_env("DB_USER"),
  password: System.get_env("DB_PASSWORD"),
  database: System.get_env("DB_NAME"),
  hostname: System.get_env("DB_HOST"),
  pool_size: 20

config :pleroma, Pleroma.Uploaders.S3,
  bucket: System.get_env("S3_BUCKET"),
  # Using CloudFront which name is same as s3 bucket name.
  # So if we set public endpoint, the URL is `https://media.pleroma.io/media.pleroma.io/filename.png`.
  public_endpoint: "https://media.pleroma.io/"

config :ex_aws, :s3,
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role],
  region: "ap-northeast-1",
  scheme: "https://"

config :pleroma, Pleroma.Upload,
  uploader: Pleroma.Uploaders.S3,
  strip_exif: false

config :pleroma, :chat,
  enabled: false

config :pleroma, :fe,
  scope_options_enabled: true

config :pleroma, :suggestions,
  enabled: true,
  third_party_engine:
    "http://vinayaka.distsn.org/cgi-bin/vinayaka-user-match-suggestions-api.cgi?{{host}}+{{user}}",
  timeout: 300_000,
  limit: 23,
  web: "https://vinayaka.distsn.org/?{{host}}+{{user}}"
