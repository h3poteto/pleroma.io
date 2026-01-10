# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Workers.ReachabilityWorker do
  use Oban.Worker,
    queue: :background,
    max_attempts: 1,
    unique: [period: :infinity, states: [:available, :scheduled], keys: [:domain]]

  alias Pleroma.HTTP
  alias Pleroma.Instances

  import Ecto.Query

  @impl true
  def perform(%Oban.Job{args: %{"domain" => domain, "phase" => phase, "attempt" => attempt}}) do
    case check_reachability(domain) do
      :ok ->
        Instances.set_reachable("https://#{domain}")
        :ok

      {:error, _} = error ->
        handle_failed_attempt(domain, phase, attempt)
        error
    end
  end

  # New jobs enter here and are immediately re-scheduled for the first phase
  @impl true
  def perform(%Oban.Job{args: %{"domain" => domain}}) do
    scheduled_at = DateTime.add(DateTime.utc_now(), 60, :second)

    %{
      "domain" => domain,
      "phase" => "phase_1min",
      "attempt" => 1
    }
    |> new(scheduled_at: scheduled_at, replace: true)
    |> Oban.insert()

    :ok
  end

  @impl true
  def timeout(_job), do: :timer.seconds(5)

  @doc "Deletes scheduled jobs to check reachability for specified instance"
  def delete_jobs_for_host(host) do
    Oban.Job
    |> where(worker: "Pleroma.Workers.ReachabilityWorker")
    |> where([j], j.args["domain"] == ^host)
    |> Oban.delete_all_jobs()
  end

  defp check_reachability(domain) do
    case HTTP.get("https://#{domain}/") do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: _status}} ->
        {:error, :unreachable}

      {:error, _} = error ->
        error
    end
  end

  defp handle_failed_attempt(_domain, "final", _attempt), do: :ok

  defp handle_failed_attempt(domain, phase, attempt) do
    {interval_minutes, max_attempts, next_phase} = get_phase_config(phase)

    if attempt >= max_attempts do
      # Move to next phase
      schedule_next_phase(domain, next_phase)
    else
      # Retry same phase with incremented attempt
      schedule_retry(domain, phase, attempt + 1, interval_minutes)
    end
  end

  defp get_phase_config("phase_1min"), do: {1, 4, "phase_15min"}
  defp get_phase_config("phase_15min"), do: {15, 4, "phase_1hour"}
  defp get_phase_config("phase_1hour"), do: {60, 4, "phase_8hour"}
  defp get_phase_config("phase_8hour"), do: {480, 4, "phase_24hour"}
  defp get_phase_config("phase_24hour"), do: {1440, 4, "final"}
  defp get_phase_config("final"), do: {nil, 0, nil}

  defp schedule_next_phase(_domain, "final"), do: :ok

  defp schedule_next_phase(domain, next_phase) do
    {interval_minutes, _max_attempts, _next_phase} = get_phase_config(next_phase)
    scheduled_at = DateTime.add(DateTime.utc_now(), interval_minutes * 60, :second)

    %{
      "domain" => domain,
      "phase" => next_phase,
      "attempt" => 1
    }
    |> new(scheduled_at: scheduled_at, replace: true)
    |> Oban.insert()
  end

  def schedule_retry(domain, phase, attempt, interval_minutes) do
    scheduled_at = DateTime.add(DateTime.utc_now(), interval_minutes * 60, :second)

    %{
      "domain" => domain,
      "phase" => phase,
      "attempt" => attempt
    }
    |> new(scheduled_at: scheduled_at, replace: true)
    |> Oban.insert()
  end
end
