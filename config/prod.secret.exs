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
  registrations_open: false,
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
  public_endpoint: "https://s3-ap-northeast-1.amazonaws.com"

config :ex_aws, :s3,
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role],
  region: "ap-northeast-1",
  scheme: "https://"

config :pleroma, Pleroma.Upload,
  uploader: Pleroma.Uploaders.S3,
  strip_exif: false
