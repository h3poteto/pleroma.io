defmodule Pleroma.SentryEventFilter do
  @behaviour Sentry.EventFilter

  # https://docs.sentry.io/clients/elixir/#filtering-events
  def exclude_exception?(%MatchError{}, :plug), do: true

  def exclude_exception?(%FunctionClauseError{}, :endpoint), do: true

  def exclude_exception?(_exception, _source), do: false
end
