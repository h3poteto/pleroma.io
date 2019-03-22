defmodule SlackLogger do
  @behaviour :gen_event

  def init(__MODULE__) do
    {:ok, configure([])}
  end

  def handle_event({_level, gl, {Logger, _, _, _}}, state) when node(gl) != node() do
    {:ok, state}
  end

  def handle_event({level, _gl, {Logger, msg, timestamps, _details}}, %{level: log_level} = state) do
    if meet_level?(level, log_level) do
      post_to_slack(level, msg, timestamps, state)
    end

    {:ok, state}
  end

  defp meet_level?(_lvl, nil), do: true
  defp meet_level?(lvl, min) do
    Logger.compare_levels(lvl, min) != :lt
  end

  def handle_call({:configure, opts}, state) do
    {:ok, :ok, configure(opts, state)}
  end

  defp configure(opts) do
    state = %{level: nil, hook_url: nil, channel: nil, username: nil}
    configure(opts, state)
  end

  defp configure(opts, state) do
    env = Application.get_env(:logger, __MODULE__, [])
    opts = Keyword.merge(env, opts)
    Application.put_env(:logger, __MODULE__, opts)

    level = Keyword.get(opts, :level)
    hook_url = retrieve_runtime_value(Keyword.get(opts, :hook_url))
    channel = Keyword.get(opts, :channel)
    username = Keyword.get(opts, :username)

    %{state | level: level, hook_url: hook_url, channel: channel, username: username}
  end

  defp retrieve_runtime_value({:system, env_key}) do
    System.get_env(env_key)
  end

  defp post_to_slack(level, message, timestamps, %{hook_url: hook_url} = state) do
    message = flatten_message(message) |> Enum.join("\n")
    {:ok, time} = parse_timex(timestamps) |> Timex.to_datetime |> Timex.format("{ISO:Extended}")
    payload = slack_payload(level, message, time, state)
    HTTPoison.post(hook_url, payload)
  end

  defp slack_payload(level, message, time, %{channel: channel, username: username}) do
    icon = slack_icon(level)
    color = slack_color(level)
    {:ok, event} = %{channel: channel,
      username: username,
      text: "*[#{time}] #{level}*",
      icon_emoji: icon,
      attachments: attachments_payload(message, color)
    }
    |> Poison.encode
    event
  end

  defp attachments_payload(message, color) do
    [%{
        color: color,
        text: "```#{message}```",
        mrkdwn_in: [
          "text"
        ]
     }
    ]
  end

  defp slack_icon(:debug), do: ":thought_balloon:"
  defp slack_icon(:info), do: ":speaker:"
  defp slack_icon(:warn), do: ":warning:"
  defp slack_icon(:error), do: ":skull_and_crossbones:"
  defp slack_color(:debug), do: "#a0a0a0"
  defp slack_color(:info), do: "good"
  defp slack_color(:warn), do: "warning"
  defp slack_color(:error), do: "danger"

  defp flatten_message(msg) do
    case msg do
      [n | body] -> ["#{n}: #{body}"]
      _ -> msg
    end
  end

  def parse_timex(timestamps) do
    {date, {h, m, s, _min}} = timestamps
    {date, {h, m, s}}
  end
end
