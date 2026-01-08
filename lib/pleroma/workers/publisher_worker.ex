# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Workers.PublisherWorker do
  alias Pleroma.Activity
  alias Pleroma.Instances
  alias Pleroma.Web.Federator

  use Oban.Worker, queue: :federator_outgoing, max_attempts: 13

  @impl true
  def perform(%Job{args: %{"op" => "publish", "activity_id" => activity_id}}) do
    activity = Activity.get_by_id(activity_id)
    Federator.perform(:publish, activity)
  end

  def perform(%Job{args: %{"op" => "publish_one", "params" => params}} = job) do
    params = Map.new(params, fn {k, v} -> {String.to_atom(k), v} end)

    # Cancel / skip the job if this server believed to be unreachable now
    if not Instances.reachable?(params.inbox) do
      {:cancel, :unreachable}
    else
      case Federator.perform(:publish_one, params) do
        {:ok, _} ->
          :ok

        {:error, _} = error ->
          # Only mark as unreachable on final failure
          if job.attempt == job.max_attempts do
            Instances.set_unreachable(params.inbox)
          end

          error

        error ->
          # Unexpected error, may have been client side
          error
      end
    end
  end

  @impl true
  def timeout(_job), do: :timer.seconds(10)

  @base_backoff 15
  @pow 5
  @impl true
  def backoff(%Job{attempt: attempt}) when is_integer(attempt) do
    backoff =
      :math.pow(attempt, @pow) +
        @base_backoff +
        :rand.uniform(2 * @base_backoff) * attempt

    trunc(backoff)
  end
end
