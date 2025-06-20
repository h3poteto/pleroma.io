#                                 .i;;;;i.
#                               iYcviii;vXY:
#                             .YXi       .i1c.
#                            .YC.     .    in7.
#                           .vc.   ......   ;1c.
#                           i7,   ..        .;1;
#                          i7,   .. ...      .Y1i
#                         ,7v     .6MMM@;     .YX,
#                        .7;.   ..IMMMMMM1     :t7.
#                       .;Y.     ;$MMMMMM9.     :tc.
#                       vY.   .. .nMMM@MMU.      ;1v.
#                      i7i   ...  .#MM@M@C. .....:71i
#                     it:   ....   $MMM@9;.,i;;;i,;tti
#                    :t7.  .....   0MMMWv.,iii:::,,;St.
#                   .nC.   .....   IMMMQ..,::::::,.,czX.
#                  .ct:   ....... .ZMMMI..,:::::::,,:76Y.
#                  c2:   ......,i..Y$M@t..:::::::,,..inZY
#                 vov   ......:ii..c$MBc..,,,,,,,,,,..iI9i
#                i9Y   ......iii:..7@MA,..,,,,,,,,,....;AA:
#               iIS.  ......:ii::..;@MI....,............;Ez.
#              .I9.  ......:i::::...8M1..................C0z.
#             .z9;  ......:i::::,.. .i:...................zWX.
#             vbv  ......,i::::,,.      ................. :AQY
#            c6Y.  .,...,::::,,..:t0@@QY. ................ :8bi
#           :6S. ..,,...,:::,,,..EMMMMMMI. ............... .;bZ,
#          :6o,  .,,,,..:::,,,..i#MMMMMM#v.................  YW2.
#         .n8i ..,,,,,,,::,,,,.. tMMMMM@C:.................. .1Wn
#         7Uc. .:::,,,,,::,,,,..   i1t;,..................... .UEi
#         7C...::::::::::::,,,,..        ....................  vSi.
#         ;1;...,,::::::,.........       ..................    Yz:
#          v97,.........                                     .voC.
#           izAotX7777777777777777777777777777777777777777Y7n92:
#             .;CoIIIIIUAA666666699999ZZZZZZZZZZZZZZZZZZZZ6ov.
#
#                          !!! ATTENTION !!!
# DO NOT EDIT THIS FILE! THIS FILE CONTAINS THE DEFAULT VALUES FOR THE CON-
# FIGURATION! EDIT YOUR SECRET FILE (either prod.secret.exs, dev.secret.exs).
#
# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
import Config

# General application configuration
config :pleroma, ecto_repos: [Pleroma.Repo]

config :pleroma, Pleroma.Repo,
  telemetry_event: [Pleroma.Repo.Instrumenter],
  migration_lock: nil

config :pleroma, Pleroma.Captcha,
  enabled: true,
  seconds_valid: 300,
  method: Pleroma.Captcha.Native

config :pleroma, Pleroma.Captcha.Kocaptcha, endpoint: "https://captcha.kotobank.ch"

# Upload configuration
config :pleroma, Pleroma.Upload,
  uploader: Pleroma.Uploaders.Local,
  filters: [Pleroma.Upload.Filter.Dedupe],
  link_name: false,
  proxy_remote: false,
  filename_display_max_length: 30,
  default_description: nil,
  base_url: nil,
  allowed_mime_types: ["image", "audio", "video"]

config :pleroma, Pleroma.Uploaders.Local, uploads: "uploads"

config :pleroma, Pleroma.Uploaders.S3,
  bucket: nil,
  bucket_namespace: nil,
  truncated_namespace: nil,
  streaming_enabled: true

config :ex_aws, :s3,
  # host: "s3.wasabisys.com", # required if not Amazon AWS
  access_key_id: nil,
  secret_access_key: nil,
  # region: "us-east-1", # may be required for Amazon AWS
  scheme: "https://"

config :pleroma, Pleroma.Uploaders.IPFS,
  post_gateway_url: "http://localhost:5001",
  get_gateway_url: "http://localhost:8080"

config :pleroma, :emoji,
  shortcode_globs: ["/emoji/custom/**/*.png"],
  pack_extensions: [".png", ".gif"],
  groups: [
    Custom: ["/emoji/*.png", "/emoji/**/*.png"]
  ],
  default_manifest: "https://git.pleroma.social/pleroma/emoji-index/raw/master/index.json",
  shared_pack_cache_seconds_per_file: 60

config :pleroma, :uri_schemes,
  valid_schemes: [
    "https",
    "http",
    "dat",
    "dweb",
    "gopher",
    "hyper",
    "ipfs",
    "ipns",
    "irc",
    "ircs",
    "magnet",
    "mailto",
    "mumble",
    "ssb",
    "xmpp"
  ]

# Configures the endpoint
config :pleroma, Pleroma.Web.Endpoint,
  url: [host: "localhost"],
  http: [
    ip: {127, 0, 0, 1}
  ],
  protocol: "https",
  secret_key_base: "aK4Abxf29xU9TTDKre9coZPUgevcVCFQJe/5xP/7Lt4BEif6idBIbjupVbOrbKxl",
  live_view: [signing_salt: "U5ELgdEwTD3n1+D5s0rY0AMg8/y1STxZ3Zvsl3bWh+oBcGrYdil0rXqPMRd3Glcq"],
  signing_salt: "CqaoopA2",
  render_errors: [view: Pleroma.Web.ErrorView, accepts: ~w(json)],
  pubsub_server: Pleroma.PubSub,
  secure_cookie_flag: true,
  extra_cookie_attrs: [
    "SameSite=Lax"
  ]

# Configures Elixir's Logger
config :logger, backends: [:console]

config :logger, :console,
  level: :debug,
  format: "\n$time $metadata[$level] $message\n",
  metadata: [:actor, :path, :type, :user]

config :logger, :ex_syslogger,
  level: :debug,
  ident: "pleroma",
  format: "$metadata[$level] $message",
  metadata: [:actor, :path, :type, :user]

config :mime, :types, %{
  "application/xml" => ["xml"],
  "application/xrd+xml" => ["xrd+xml"],
  "application/jrd+json" => ["jrd+json"],
  "application/activity+json" => ["activity+json"],
  "application/ld+json" => ["activity+json"],
  # Can be removed when bumping MIME past 2.0.5
  # see https://akkoma.dev/AkkomaGang/akkoma/issues/657
  "image/apng" => ["apng"]
}

config :tesla, adapter: Tesla.Adapter.Hackney

# Configures http settings, upstream proxy etc.
config :pleroma, :http,
  proxy_url: nil,
  send_user_agent: true,
  user_agent: :default,
  adapter: []

config :pleroma, :instance,
  name: "Pleroma",
  email: "example@example.com",
  notify_email: "noreply@example.com",
  description: "Pleroma: An efficient and flexible fediverse server",
  short_description: "",
  background_image: "/images/city.jpg",
  instance_thumbnail: "/instance/thumbnail.jpeg",
  favicon: "/favicon.png",
  limit: 5_000,
  description_limit: 5_000,
  remote_limit: 100_000,
  upload_limit: 16_000_000,
  avatar_upload_limit: 2_000_000,
  background_upload_limit: 4_000_000,
  banner_upload_limit: 4_000_000,
  poll_limits: %{
    max_options: 20,
    max_option_chars: 200,
    min_expiration: 0,
    max_expiration: 365 * 24 * 60 * 60
  },
  registrations_open: true,
  invites_enabled: false,
  account_activation_required: false,
  account_approval_required: false,
  federating: true,
  federation_incoming_replies_max_depth: 100,
  federation_reachability_timeout_days: 7,
  allow_relay: true,
  public: true,
  quarantined_instances: [],
  rejected_instances: [],
  static_dir: "instance/static/",
  allowed_post_formats: [
    "text/plain",
    "text/html",
    "text/markdown",
    "text/bbcode"
  ],
  autofollowed_nicknames: [],
  autofollowing_nicknames: [],
  max_pinned_statuses: 1,
  attachment_links: false,
  max_report_comment_size: 1000,
  report_strip_status: true,
  safe_dm_mentions: false,
  healthcheck: false,
  remote_post_retention_days: 90,
  skip_thread_containment: true,
  limit_to_local_content: :unauthenticated,
  user_bio_length: 5000,
  user_name_length: 100,
  max_account_fields: 10,
  max_remote_account_fields: 20,
  account_field_name_length: 512,
  account_field_value_length: 2048,
  registration_reason_length: 500,
  external_user_synchronization: true,
  extended_nickname_format: true,
  cleanup_attachments: false,
  multi_factor_authentication: [
    totp: [
      # digits 6 or 8
      digits: 6,
      period: 30
    ],
    backup_codes: [
      number: 5,
      length: 16
    ]
  ],
  show_reactions: true,
  password_reset_token_validity: 60 * 60 * 24,
  profile_directory: true,
  admin_privileges: [
    :users_read,
    :users_manage_invites,
    :users_manage_activation_state,
    :users_manage_tags,
    :users_manage_credentials,
    :users_delete,
    :messages_read,
    :messages_delete,
    :instances_delete,
    :reports_manage_reports,
    :moderation_log_read,
    :announcements_manage_announcements,
    :emoji_manage_emoji,
    :statistics_read
  ],
  moderator_privileges: [:messages_delete, :reports_manage_reports],
  max_endorsed_users: 20,
  birthday_required: false,
  birthday_min_age: 0,
  max_media_attachments: 1_000

config :pleroma, :welcome,
  direct_message: [
    enabled: false,
    sender_nickname: nil,
    message: nil
  ],
  chat_message: [
    enabled: false,
    sender_nickname: nil,
    message: nil
  ],
  email: [
    enabled: false,
    sender: nil,
    subject: "Welcome to <%= instance_name %>",
    html: "Welcome to <%= instance_name %>",
    text: "Welcome to <%= instance_name %>"
  ]

config :pleroma, :feed,
  post_title: %{
    max_length: 100,
    omission: "..."
  }

config :pleroma, :markup,
  # XXX - unfortunately, inline images must be enabled by default right now, because
  # of custom emoji.  Issue #275 discusses defanging that somehow.
  allow_inline_images: true,
  allow_headings: false,
  allow_tables: false,
  allow_fonts: false,
  scrub_policy: [
    Pleroma.HTML.Scrubber.Default,
    Pleroma.HTML.Transform.MediaProxy
  ]

config :pleroma, :frontend_configurations,
  pleroma_fe: %{
    alwaysShowSubjectInput: true,
    background: "/images/city.jpg",
    collapseMessageWithSubject: false,
    disableChat: false,
    greentext: false,
    hideFilteredStatuses: false,
    hideMutedPosts: false,
    hidePostStats: false,
    hideSitename: false,
    hideUserStats: false,
    loginMethod: "password",
    logo: "/static/logo.svg",
    logoMargin: ".1em",
    logoMask: true,
    minimalScopesMode: false,
    noAttachmentLinks: false,
    nsfwCensorImage: "",
    postContentType: "text/plain",
    redirectRootLogin: "/main/friends",
    redirectRootNoLogin: "/main/all",
    scopeCopy: true,
    sidebarRight: false,
    showFeaturesPanel: true,
    showInstanceSpecificPanel: false,
    subjectLineBehavior: "email",
    theme: "pleroma-dark",
    webPushNotifications: false
  }

config :pleroma, :assets,
  mascots: [
    pleroma_fox_tan: %{
      url: "/images/pleroma-fox-tan-smol.png",
      mime_type: "image/png"
    },
    pleroma_fox_tan_shy: %{
      url: "/images/pleroma-fox-tan-shy.png",
      mime_type: "image/png"
    }
  ],
  default_mascot: :pleroma_fox_tan

config :pleroma, :manifest,
  icons: [
    %{
      src: "/static/logo.svg",
      sizes: "512x512",
      purpose: "any",
      type: "image/svg+xml"
    }
  ],
  theme_color: "#282c37",
  background_color: "#191b22"

config :pleroma, :activitypub,
  unfollow_blocked: true,
  outgoing_blocks: true,
  blockers_visible: true,
  follow_handshake_timeout: 500,
  note_replies_output_limit: 5,
  sign_object_fetches: true,
  authorized_fetch_mode: false,
  client_api_enabled: false

config :pleroma, :streamer,
  workers: 3,
  overflow_workers: 2

config :pleroma, :user, deny_follow_blocked: true

config :pleroma, :mrf_normalize_markup, scrub_policy: Pleroma.HTML.Scrubber.Default

config :pleroma, :mrf_rejectnonpublic,
  allow_followersonly: false,
  allow_direct: false

config :pleroma, :mrf_hellthread,
  delist_threshold: 10,
  reject_threshold: 20

config :pleroma, :mrf_simple,
  media_removal: [],
  media_nsfw: [],
  federated_timeline_removal: [],
  report_removal: [],
  reject: [],
  followers_only: [],
  accept: [],
  avatar_removal: [],
  banner_removal: [],
  reject_deletes: []

config :pleroma, :mrf_keyword,
  reject: [],
  federated_timeline_removal: [],
  replace: []

config :pleroma, :mrf_emoji,
  remove_url: [],
  remove_shortcode: [],
  federated_timeline_removal_url: [],
  federated_timeline_removal_shortcode: []

config :pleroma, :mrf_hashtag,
  sensitive: ["nsfw"],
  reject: [],
  federated_timeline_removal: []

config :pleroma, :mrf_subchain, match_actor: %{}

config :pleroma, :mrf_activity_expiration, days: 365

config :pleroma, :mrf_vocabulary,
  accept: [],
  reject: []

# threshold of 7 days
config :pleroma, :mrf_object_age,
  threshold: 604_800,
  actions: [:delist, :strip_followers]

config :pleroma, :mrf_nsfw_api,
  url: "http://127.0.0.1:5000/",
  threshold: 0.7,
  mark_sensitive: true,
  unlist: false,
  reject: false

config :pleroma, :mrf_follow_bot, follower_nickname: nil

config :pleroma, :mrf_inline_quote, template: "<bdi>RT:</bdi> {url}"

config :pleroma, :mrf_remote_report,
  reject_all: false,
  reject_anonymous: true,
  reject_empty_message: true

config :pleroma, :mrf_force_mention,
  mention_parent: true,
  mention_quoted: true

config :pleroma, :mrf_antimentionspam, user_age_limit: 30_000

config :pleroma, :rich_media,
  enabled: true,
  ignore_hosts: [],
  ignore_tld: ["local", "localdomain", "lan"],
  parsers: [
    Pleroma.Web.RichMedia.Parsers.TwitterCard,
    Pleroma.Web.RichMedia.Parsers.OEmbed
  ],
  timeout: 5_000,
  ttl_setters: [
    Pleroma.Web.RichMedia.Parser.TTL.AwsSignedUrl,
    Pleroma.Web.RichMedia.Parser.TTL.Opengraph
  ],
  max_body: 5_000_000

config :pleroma, :media_proxy,
  enabled: false,
  invalidation: [
    enabled: false,
    provider: Pleroma.Web.MediaProxy.Invalidation.Script
  ],
  proxy_opts: [
    redirect_on_failure: false,
    max_body_length: 25 * 1_048_576,
    # Note: max_read_duration defaults to Pleroma.ReverseProxy.max_read_duration_default/1
    max_read_duration: 30_000,
    http: [
      follow_redirect: true,
      pool: :media
    ]
  ],
  whitelist: []

config :pleroma, Pleroma.Web.MediaProxy.Invalidation.Http,
  method: :purge,
  headers: [],
  options: []

config :pleroma, Pleroma.Web.MediaProxy.Invalidation.Script,
  script_path: nil,
  url_format: nil

# Note: media preview proxy depends on media proxy to be enabled
config :pleroma, :media_preview_proxy,
  enabled: false,
  thumbnail_max_width: 600,
  thumbnail_max_height: 600,
  image_quality: 85,
  min_content_length: 100 * 1024

config :pleroma, :shout,
  enabled: true,
  limit: 5_000

config :phoenix, :format_encoders, json: Jason, "activity+json": Jason

config :phoenix, :json_library, Jason

config :phoenix, :filter_parameters, ["password", "confirm"]

config :pleroma, :gopher,
  enabled: false,
  ip: {0, 0, 0, 0},
  port: 9999

config :pleroma, Pleroma.Web.Metadata,
  providers: [
    Pleroma.Web.Metadata.Providers.OpenGraph,
    Pleroma.Web.Metadata.Providers.TwitterCard
  ],
  unfurl_nsfw: false

config :pleroma, Pleroma.Web.Preload,
  providers: [
    Pleroma.Web.Preload.Providers.Instance
  ]

config :pleroma, :http_security,
  enabled: true,
  sts: false,
  sts_max_age: 31_536_000,
  ct_max_age: 2_592_000,
  referrer_policy: "same-origin",
  allow_unsafe_eval: false

config :cors_plug,
  max_age: 86_400,
  methods: ["POST", "PUT", "DELETE", "GET", "PATCH", "OPTIONS"],
  expose: [
    "Link",
    "X-RateLimit-Reset",
    "X-RateLimit-Limit",
    "X-RateLimit-Remaining",
    "X-Request-Id",
    "Idempotency-Key"
  ],
  credentials: true,
  headers: ["Authorization", "Content-Type", "Idempotency-Key"]

config :pleroma, Pleroma.User,
  restricted_nicknames: [
    ".well-known",
    "~",
    "about",
    "activities",
    "api",
    "auth",
    "check_password",
    "dev",
    "friend-requests",
    "inbox",
    "internal",
    "main",
    "media",
    "nodeinfo",
    "notice",
    "oauth",
    "objects",
    "ostatus_subscribe",
    "pleroma",
    "proxy",
    "push",
    "registration",
    "relay",
    "settings",
    "status",
    "tag",
    "user-search",
    "user_exists",
    "users",
    "web",
    "verify_credentials",
    "update_credentials",
    "relationships",
    "search",
    "confirmation_resend",
    "mfa"
  ],
  email_blacklist: []

# The Pruner :max_age must be longer than Worker :unique
# value or it cannot enforce uniqueness.
config :pleroma, Oban,
  repo: Pleroma.Repo,
  log: false,
  queues: [
    activity_expiration: 10,
    federator_incoming: 5,
    federator_outgoing: 25,
    web_push: 50,
    background: 20,
    search_indexing: [limit: 10, paused: true],
    slow: 5
  ],
  plugins: [{Oban.Plugins.Pruner, max_age: 900}],
  crontab: [
    {"0 0 * * 0", Pleroma.Workers.Cron.DigestEmailsWorker},
    {"0 0 * * *", Pleroma.Workers.Cron.NewUsersDigestWorker},
    {"*/10 * * * *", Pleroma.Workers.Cron.AppCleanupWorker}
  ]

config :pleroma, Pleroma.Formatter,
  class: false,
  rel: "ugc",
  new_window: false,
  truncate: false,
  strip_prefix: false,
  extra: true,
  validate_tld: :no_scheme

config :pleroma, :ldap,
  enabled: System.get_env("LDAP_ENABLED") == "true",
  host: System.get_env("LDAP_HOST", "localhost"),
  port: String.to_integer(System.get_env("LDAP_PORT", "389")),
  ssl: System.get_env("LDAP_SSL") == "true",
  sslopts: [],
  tls: System.get_env("LDAP_TLS") == "true",
  tlsopts: [],
  base: System.get_env("LDAP_BASE", "dc=example,dc=com"),
  uid: System.get_env("LDAP_UID", "cn"),
  # defaults to CAStore's Mozilla roots
  cacertfile: System.get_env("LDAP_CACERTFILE", nil),
  mail: System.get_env("LDAP_MAIL", "mail")

oauth_consumer_strategies =
  System.get_env("OAUTH_CONSUMER_STRATEGIES")
  |> to_string()
  |> String.split()
  |> Enum.map(&hd(String.split(&1, ":")))

ueberauth_providers =
  for strategy <- oauth_consumer_strategies do
    strategy_module_name = "Elixir.Ueberauth.Strategy.#{String.capitalize(strategy)}"
    strategy_module = String.to_atom(strategy_module_name)
    {String.to_atom(strategy), {strategy_module, [callback_params: ["state"]]}}
  end

config :ueberauth,
       Ueberauth,
       base_path: "/oauth",
       providers: ueberauth_providers

config :pleroma, :auth, oauth_consumer_strategies: oauth_consumer_strategies

config :pleroma, Pleroma.Emails.Mailer, adapter: Swoosh.Adapters.Sendmail, enabled: false

config :pleroma, Pleroma.Emails.UserEmail,
  logo: nil,
  styling: %{
    link_color: "#d8a070",
    background_color: "#2C3645",
    content_background_color: "#1B2635",
    header_color: "#d8a070",
    text_color: "#b9b9ba",
    text_muted_color: "#b9b9ba"
  }

config :pleroma, Pleroma.Emails.NewUsersDigestEmail, enabled: false

config :pleroma, Pleroma.PromEx,
  disabled: false,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: [
    host: System.get_env("GRAFANA_HOST", "http://localhost:3000"),
    auth_token: System.get_env("GRAFANA_TOKEN"),
    upload_dashboards_on_start: false,
    folder_name: "BEAM",
    annotate_app_lifecycle: true
  ],
  metrics_server: [
    port: 4021,
    path: "/metrics",
    protocol: :http,
    pool_size: 5,
    cowboy_opts: [],
    auth_strategy: :none
  ],
  datasource: "Prometheus"

config :pleroma, Pleroma.ScheduledActivity,
  daily_user_limit: 25,
  total_user_limit: 300,
  enabled: true

config :pleroma, :email_notifications,
  digest: %{
    active: false,
    interval: 7,
    inactivity_threshold: 7
  }

config :pleroma, :oauth2,
  token_expires_in: 3600 * 24 * 365 * 100,
  issue_new_refresh_token: true,
  clean_expired_tokens: false

config :pleroma, :database, rum_enabled: false

config :pleroma, :features, improved_hashtag_timeline: :auto

config :pleroma, :populate_hashtags_table, fault_rate_allowance: 0.01

config :pleroma, :delete_context_objects, fault_rate_allowance: 0.01

config :pleroma, :env, Mix.env()

config :http_signatures,
  adapter: Pleroma.Signature

config :pleroma, :rate_limit,
  authentication: {60_000, 15},
  timeline: {500, 3},
  search: [{1000, 10}, {1000, 30}],
  app_account_creation: {1_800_000, 25},
  oauth_app_creation: {900_000, 5},
  relations_actions: {10_000, 10},
  relation_id_action: {60_000, 2},
  statuses_actions: {10_000, 15},
  status_id_action: {60_000, 3},
  password_reset: {1_800_000, 5},
  account_confirmation_resend: {8_640_000, 5},
  ap_routes: {60_000, 15}

config :pleroma, Pleroma.Workers.PurgeExpiredActivity, enabled: true, min_lifetime: 600

config :pleroma, Pleroma.Web.Plugs.RemoteIp,
  enabled: true,
  headers: ["x-forwarded-for"],
  proxies: [],
  reserved: [
    "127.0.0.0/8",
    "::1/128",
    "fc00::/7",
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16"
  ]

config :pleroma, :static_fe, enabled: false

# Example of frontend configuration
# This example will make us serve the primary frontend from the
# frontends directory within your `:pleroma, :instance, static_dir`.
# e.g., instance/static/frontends/pleroma/develop/
#
# With no frontend configuration, the bundled files from the `static` directory will
# be used.
#
# config :pleroma, :frontends,
# primary: %{"name" => "pleroma-fe", "ref" => "develop"},
# admin: %{"name" => "admin-fe", "ref" => "stable"},
# available: %{...}

config :pleroma, :frontends,
  available: %{
    "kenoma" => %{
      "name" => "kenoma",
      "git" => "https://git.pleroma.social/lambadalambda/kenoma",
      "build_url" =>
        "https://git.pleroma.social/lambadalambda/kenoma/-/jobs/artifacts/${ref}/download?job=build",
      "ref" => "master"
    },
    "pleroma-fe" => %{
      "name" => "pleroma-fe",
      "git" => "https://git.pleroma.social/pleroma/pleroma-fe",
      "build_url" =>
        "https://git.pleroma.social/pleroma/pleroma-fe/-/jobs/artifacts/${ref}/download?job=build",
      "ref" => "develop"
    },
    "fedi-fe" => %{
      "name" => "fedi-fe",
      "git" => "https://git.pleroma.social/pleroma/fedi-fe",
      "build_url" =>
        "https://git.pleroma.social/pleroma/fedi-fe/-/jobs/artifacts/${ref}/download?job=build_release",
      "ref" => "master",
      "custom-http-headers" => [
        {"service-worker-allowed", "/"}
      ]
    },
    "admin-fe" => %{
      "name" => "admin-fe",
      "git" => "https://git.pleroma.social/pleroma/admin-fe",
      "build_url" =>
        "https://git.pleroma.social/pleroma/admin-fe/-/jobs/artifacts/${ref}/download?job=build",
      "ref" => "develop"
    },
    "soapbox" => %{
      "name" => "soapbox",
      "git" => "https://gitlab.com/soapbox-pub/soapbox",
      "build_url" =>
        "https://gitlab.com/soapbox-pub/soapbox/-/jobs/artifacts/${ref}/download?job=build-production",
      "ref" => "v3.0.0-beta.1",
      "build_dir" => "static"
    },
    "glitch-lily" => %{
      "name" => "glitch-lily",
      "git" => "https://lily-is.land/infra/glitch-lily",
      "build_url" =>
        "https://lily-is.land/infra/glitch-lily/-/jobs/artifacts/${ref}/download?job=build",
      "ref" => "servant",
      "build_dir" => "public"
    },
    "pl-fe" => %{
      "name" => "pl-fe",
      "git" => "https://github.com/mkljczk/pl-fe",
      "build_url" => "https://pl.mkljczk.pl/pl-fe.zip",
      "ref" => "develop",
      "build_dir" => "."
    }
  }

config :pleroma, :web_cache_ttl,
  activity_pub: nil,
  activity_pub_question: 30_000

config :pleroma, :modules, runtime_dir: "instance/modules"

config :pleroma, configurable_from_database: false

config :pleroma, Pleroma.Repo,
  parameters: [gin_fuzzy_search_limit: "500", jit: "off"],
  prepare: :unnamed

config :pleroma, :connections_pool,
  reclaim_multiplier: 0.1,
  connection_acquisition_wait: 250,
  connection_acquisition_retries: 5,
  max_connections: 250,
  max_idle_time: 30_000,
  retry: 0,
  connect_timeout: 5_000

config :pleroma, :pools,
  federation: [
    size: 75,
    max_waiting: 20,
    recv_timeout: 10_000
  ],
  media: [
    size: 75,
    max_waiting: 20,
    recv_timeout: 15_000
  ],
  rich_media: [
    size: 25,
    max_waiting: 20,
    recv_timeout: 15_000
  ],
  upload: [
    size: 25,
    max_waiting: 20,
    recv_timeout: 15_000
  ],
  default: [
    size: 50,
    max_waiting: 2,
    recv_timeout: 5_000
  ]

config :pleroma, :hackney_pools,
  federation: [
    max_connections: 50,
    timeout: 10_000
  ],
  media: [
    max_connections: 50,
    timeout: 15_000
  ],
  rich_media: [
    max_connections: 50,
    timeout: 15_000
  ],
  upload: [
    max_connections: 25,
    timeout: 15_000
  ]

config :pleroma, :majic_pool, size: 2

private_instance? = :if_instance_is_private

config :pleroma, :restrict_unauthenticated,
  timelines: %{local: private_instance?, federated: private_instance?},
  profiles: %{local: private_instance?, remote: private_instance?},
  activities: %{local: private_instance?, remote: private_instance?}

config :pleroma, Pleroma.Web.ApiSpec.CastAndValidate, strict: false

config :pleroma, :mrf,
  policies: [
    Pleroma.Web.ActivityPub.MRF.ObjectAgePolicy,
    Pleroma.Web.ActivityPub.MRF.TagPolicy,
    Pleroma.Web.ActivityPub.MRF.InlineQuotePolicy
  ],
  transparency: true,
  transparency_exclusions: []

config :tzdata, :http_client, Pleroma.HTTP.Tzdata

config :ex_aws, http_client: Pleroma.HTTP.ExAws

config :web_push_encryption, http_client: Pleroma.HTTP.WebPush

config :pleroma, :instances_favicons, enabled: false

config :floki, :html_parser, Floki.HTMLParser.FastHtml

config :pleroma, Pleroma.Web.Auth.Authenticator, Pleroma.Web.Auth.PleromaAuthenticator

config :pleroma, Pleroma.User.Backup,
  purge_after_days: 30,
  limit_days: 7,
  dir: nil,
  process_chunk_size: 100,
  timeout: :timer.minutes(30)

config :pleroma, ConcurrentLimiter, [
  {Pleroma.Search, [max_running: 30, max_waiting: 50]}
]

config :pleroma, Pleroma.Web.WebFinger, domain: nil, update_nickname_on_user_fetch: true

config :rollbax,
  enabled: false

config :pleroma, Pleroma.Search, module: Pleroma.Search.DatabaseSearch

config :pleroma, Pleroma.Search.Meilisearch,
  url: "http://127.0.0.1:7700/",
  private_key: nil,
  initial_indexing_chunk_size: 100_000

config :pleroma, Pleroma.Application,
  background_migrators: true,
  internal_fetch: true,
  load_custom_modules: true,
  max_restarts: 3,
  streamer_registry: true

config :pleroma, Pleroma.Uploaders.Uploader, timeout: 30_000

config :pleroma, Pleroma.Search.QdrantSearch,
  qdrant_url: "http://127.0.0.1:6333/",
  qdrant_api_key: "",
  openai_url: "http://127.0.0.1:11345",
  # The healthcheck url has to be set to nil when used with the real openai
  # API, as it doesn't have a healthcheck endpoint.
  openai_healthcheck_url: "http://127.0.0.1:11345/health",
  openai_model: "snowflake/snowflake-arctic-embed-xs",
  openai_api_key: "",
  qdrant_index_configuration: %{
    vectors: %{size: 384, distance: "Cosine"}
  }

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
