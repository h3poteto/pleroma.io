defmodule Pleroma.Mixfile do
  use Mix.Project

  def project do
    [
      app: :pleroma,
      version: version("2.9.1"),
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers(),
      elixirc_options: [warnings_as_errors: warnings_as_errors(), prune_code_paths: false],
      xref: [exclude: [:eldap]],
      dialyzer: [plt_add_apps: [:mix, :eldap]],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: :covertool, summary: true],
      # Docs
      name: "Pleroma",
      homepage_url: "https://pleroma.social/",
      source_url: "https://git.pleroma.social/pleroma/pleroma",
      docs: [
        source_url_pattern:
          "https://git.pleroma.social/pleroma/pleroma/blob/develop/%{path}#L%{line}",
        logo: "priv/static/images/logo.png",
        extras: ["README.md", "CHANGELOG.md"] ++ Path.wildcard("docs/**/*.md"),
        groups_for_extras: [
          "Installation manuals": Path.wildcard("docs/installation/*.md"),
          Configuration: Path.wildcard("docs/config/*.md"),
          Administration: Path.wildcard("docs/admin/*.md"),
          "Pleroma's APIs and Mastodon API extensions": Path.wildcard("docs/api/*.md")
        ],
        main: "readme",
        output: "priv/static/doc"
      ],
      releases: [
        pleroma: [
          include_executables_for: [:unix],
          applications: [
            ex_syslogger: :load,
            syslog: :load,
            eldap: :transient,
            opentelemetry: :temporary
          ],
          steps: [:assemble, &put_otp_version/1, &copy_files/1, &copy_nginx_config/1],
          config_providers: [{Pleroma.Config.ReleaseRuntimeProvider, []}]
        ]
      ]
    ]
  end

  def put_otp_version(%{path: target_path} = release) do
    File.write!(
      Path.join([target_path, "OTP_VERSION"]),
      Pleroma.OTPVersion.version()
    )

    release
  end

  def copy_files(%{path: target_path} = release) do
    File.cp_r!("./rel/files", target_path)
    release
  end

  def copy_nginx_config(%{path: target_path} = release) do
    File.cp!(
      "./installation/pleroma.nginx",
      Path.join([target_path, "installation", "pleroma.nginx"])
    )

    release
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Pleroma.Application, []},
      extra_applications:
        [
          :logger,
          :runtime_tools,
          :comeonin,
          :fast_sanitize,
          :os_mon,
          :ssl,
          :eldap
        ] ++ logger_application(),
      included_applications: [:ex_syslogger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:benchmark), do: ["lib", "benchmarks", "priv/scrubbers"]
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp warnings_as_errors, do: System.get_env("CI") == "true"

  # Specifies OAuth dependencies.
  defp oauth_deps do
    oauth_strategy_packages =
      System.get_env("OAUTH_CONSUMER_STRATEGIES")
      |> to_string()
      |> String.split()
      |> Enum.map(fn strategy_entry ->
        with [_strategy, dependency] <- String.split(strategy_entry, ":") do
          dependency
        else
          [strategy] -> "ueberauth_#{strategy}"
        end
      end)

    for s <- oauth_strategy_packages, do: {String.to_atom(s), ">= 0.0.0"}
  end

  defp logger_application do
    if Version.match?(System.version(), "<1.15.0-rc.0") do
      []
    else
      [:logger_backends]
    end
  end

  defp logger_deps do
    if Version.match?(System.version(), "<1.15.0-rc.0") do
      []
    else
      [{:logger_backends, "~> 1.0"}]
    end
  end

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix,
       git: "https://github.com/feld/phoenix", branch: "v1.7.14-websocket-headers", override: true},
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.10"},
      {:ecto_enum, "~> 1.4"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 3.3"},
      {:phoenix_live_view, "~> 0.19.0"},
      {:phoenix_live_dashboard, "~> 0.8.0"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:tzdata, "~> 1.0.3"},
      {:plug_cowboy, "~> 2.5"},
      {:oban, "~> 2.18.0"},
      {:gettext, "~> 0.20"},
      {:bcrypt_elixir, "~> 2.2"},
      {:trailing_format_plug, "~> 0.0.7"},
      {:fast_sanitize, "~> 0.2.0"},
      {:html_entities, "~> 0.5", override: true},
      {:calendar, "~> 1.0"},
      {:cachex, "~> 3.2"},
      {:tesla, "~> 1.11"},
      {:castore, "~> 1.0"},
      {:cowlib, "~> 2.9", override: true},
      {:gun, "~> 2.0.0-rc.1", override: true},
      {:finch, "~> 0.15"},
      {:jason, "~> 1.2"},
      {:mogrify, "~> 0.9.0", override: "true"},
      {:ex_aws, "~> 2.1.6"},
      {:ex_aws_s3, "~> 2.0"},
      {:ex_aws_sts, "~>2.1"},
      {:sweet_xml, "~> 0.7.2"},
      {:configparser_ex, "~> 4.0"},
      # earmark 1.4.23 requires Elixir 1.12+
      {:earmark, "1.4.46"},
      {:bbcode_pleroma, "~> 0.2.0"},
      {:cors_plug, "~> 2.0"},
      {:web_push_encryption, "~> 0.3.1"},
      {:swoosh, "~> 1.16.9"},
      {:phoenix_swoosh, "~> 1.1"},
      {:gen_smtp, "~> 0.13"},
      {:mua, "~> 0.2.0"},
      {:mail, "~> 0.3.0"},
      {:ex_syslogger, "~> 1.4"},
      {:floki, "~> 0.35"},
      {:timex, "~> 3.6"},
      {:ueberauth, "~> 0.4"},
      {:linkify, "~> 0.5.3"},
      {:http_signatures, "~> 0.1.2"},
      {:telemetry, "~> 1.0.0", override: true},
      {:poolboy, "~> 1.5"},
      {:prom_ex, "~> 1.9"},
      {:recon, "~> 2.5"},
      {:joken, "~> 2.0"},
      {:pot, "~> 1.0"},
      {:ex_const, "~> 0.2"},
      {:plug_static_index_html, "~> 1.0.0"},
      {:flake_id, "~> 0.1.0"},
      {:concurrent_limiter, "~> 0.1.1"},
      {:remote_ip,
       git: "https://git.pleroma.social/pleroma/remote_ip.git",
       ref: "b647d0deecaa3acb140854fe4bda5b7e1dc6d1c8"},
      {:captcha,
       git: "https://git.pleroma.social/pleroma/elixir-libraries/elixir-captcha.git",
       ref: "6630c42aaaab124e697b4e513190c89d8b64e410"},
      {:rollbax, github: "ForzaElixir/rollbax"},
      {:restarter, path: "./restarter"},
      {:majic, "~> 1.0"},
      {:open_api_spex, "~> 3.16"},
      {:ecto_psql_extras, "~> 0.6"},
      {:vix, "~> 0.26.0"},
      {:elixir_make, "~> 0.7.7", override: true},
      {:blurhash, "~> 0.1.0", hex: :rinpatch_blurhash},
      {:exile, "~> 0.10.0"},
      {:bandit, "~> 1.5.2"},
      {:websock_adapter, "~> 0.5.6"},
      {:oban_live_dashboard, "~> 0.1.1"},
      {:multipart, "~> 0.4.0", optional: true},
      {:argon2_elixir, "~> 4.0"},

      # open telemetry
      {:opentelemetry, "~> 1.5.0"},
      {:opentelemetry_phoenix, "~> 1.2"},
      {:opentelemetry_cowboy, "~> 0.3.0"},
      {:opentelemetry_exporter, "~> 1.8.0"},
      {:opentelemetry_ecto, "~> 1.2.0"},
      {:opentelemetry_oban, "~> 1.1"},
      # telemetry
      {:telemetry_metrics_prometheus, "~> 1.0"},

      ## dev & test
      {:phoenix_live_reload, "~> 1.3.3", only: :dev},
      {:poison, "~> 3.0", only: :test},
      {:ex_doc, "~> 0.22", only: :dev, runtime: false},
      {:ex_machina, "~> 2.4", only: :test},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:mock, "~> 0.3.5", only: :test},
      {:covertool, "~> 2.0", only: :test},
      {:hackney, "~> 1.18.0", override: true},
      {:mox, "~> 1.0", only: :test},
      {:websockex, "~> 0.4.3", only: :test},
      {:benchee, "~> 1.0", only: :benchmark},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ] ++ oauth_deps() ++ logger_deps()
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to create, migrate and run the seeds file at once:
  #
  #     $ mix ecto.setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate", "test"],
      docs: ["pleroma.docs", "docs"],
      analyze: ["credo --strict --only=warnings,todo,fixme,consistency,readability"],
      copyright: &add_copyright/1,
      "copyright.bump": &bump_copyright/1
    ]
  end

  # Builds a version string made of:
  # * the application version
  # * a pre-release if ahead of the tag: the describe string (-count-commithash)
  # * branch name
  # * build metadata:
  #   * a build name if `PLEROMA_BUILD_NAME` or `:pleroma, :build_name` is defined
  #   * the mix environment if different than prod
  defp version(version) do
    identifier_filter = ~r/[^0-9a-z\-]+/i

    git_available? = match?({_output, 0}, System.cmd("sh", ["-c", "command -v git"]))
    dotgit_present? = File.exists?(".git")

    git_pre_release =
      if git_available? and dotgit_present? do
        {tag, tag_err} =
          System.cmd("git", ["describe", "--tags", "--abbrev=0"], stderr_to_stdout: true)

        {describe, describe_err} = System.cmd("git", ["describe", "--tags", "--abbrev=8"])
        {commit_hash, commit_hash_err} = System.cmd("git", ["rev-parse", "--short", "HEAD"])

        # Pre-release version, denoted from patch version with a hyphen
        cond do
          tag_err == 0 and describe_err == 0 ->
            describe
            |> String.trim()
            |> String.replace(String.trim(tag), "")
            |> String.trim_leading("-")
            |> String.trim()

          commit_hash_err == 0 ->
            "0-g" <> String.trim(commit_hash)

          true ->
            nil
        end
      end

    # Branch name as pre-release version component, denoted with a dot
    branch_name =
      with true <- git_available?,
           true <- dotgit_present?,
           {branch_name, 0} <- System.cmd("git", ["rev-parse", "--abbrev-ref", "HEAD"]),
           branch_name <- String.trim(branch_name),
           branch_name <- System.get_env("PLEROMA_BUILD_BRANCH") || branch_name,
           true <-
             !Enum.any?(["master", "HEAD", "release/", "stable"], fn name ->
               String.starts_with?(name, branch_name)
             end) do
        branch_name =
          branch_name
          |> String.trim()
          |> String.replace(identifier_filter, "-")

        branch_name
      else
        _ -> ""
      end

    build_name =
      cond do
        name = Application.get_env(:pleroma, :build_name) -> name
        name = System.get_env("PLEROMA_BUILD_NAME") -> name
        true -> nil
      end

    env_name = if Mix.env() != :prod, do: to_string(Mix.env())
    env_override = System.get_env("PLEROMA_BUILD_ENV")

    env_name =
      case env_override do
        nil -> env_name
        env_override when env_override in ["", "prod"] -> nil
        env_override -> env_override
      end

    # Pre-release version, denoted by appending a hyphen
    # and a series of dot separated identifiers
    pre_release =
      [git_pre_release, branch_name]
      |> Enum.filter(fn string -> string && string != "" end)
      |> Enum.join(".")
      |> (fn
            "" -> nil
            string -> "-" <> String.replace(string, identifier_filter, "-")
          end).()

    # Build metadata, denoted with a plus sign
    build_metadata =
      [build_name, env_name]
      |> Enum.filter(fn string -> string && string != "" end)
      |> Enum.join(".")
      |> (fn
            "" -> nil
            string -> "+" <> String.replace(string, identifier_filter, "-")
          end).()

    [version, pre_release, build_metadata]
    |> Enum.filter(fn string -> string && string != "" end)
    |> Enum.join()
  end

  defp add_copyright(_) do
    year = NaiveDateTime.utc_now().year
    template = ~s[\
# Pleroma: A lightweight social networking server
# Copyright © 2017-#{year} Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

] |> String.replace("\n", "\\n")

    find = "find lib test priv -type f \\( -name '*.ex' -or -name '*.exs' \\) -exec "
    grep = "grep -L '# Copyright © [0-9\-]* Pleroma' {} \\;"
    xargs = "xargs -n1 sed -i'' '1s;^;#{template};'"

    :os.cmd(String.to_charlist("#{find}#{grep} | #{xargs}"))
  end

  defp bump_copyright(_) do
    year = NaiveDateTime.utc_now().year
    find = "find lib test priv -type f \\( -name '*.ex' -or -name '*.exs' \\)"

    xargs =
      "xargs sed -i'' 's;# Copyright © [0-9\-]* Pleroma.*$;# Copyright © 2017-#{year} Pleroma Authors <https://pleroma.social/>;'"

    :os.cmd(String.to_charlist("#{find} | #{xargs}"))
  end
end
