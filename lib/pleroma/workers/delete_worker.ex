# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Workers.DeleteWorker do
  alias Pleroma.User

  use Oban.Worker, queue: :slow

  @impl true
  def perform(%Job{args: %{"op" => "delete_user", "user_id" => user_id}}) do
    user = User.get_cached_by_id(user_id)
    User.perform(:delete, user)
  end

  def perform(%Job{args: %{"op" => "delete_instance", "host" => host}}) do
    # Schedule the per-user deletion jobs
    Pleroma.Repo.transaction(fn ->
      User.Query.build(%{nickname: "@#{host}"})
      |> Pleroma.Repo.all()
      |> Enum.each(fn user ->
        %{"op" => "delete_user", "user_id" => user.id}
        |> __MODULE__.new()
        |> Oban.insert()
      end)

      # Delete the instance from the Instances table
      case Pleroma.Repo.get_by(Pleroma.Instances.Instance, host: host) do
        nil -> :ok
        instance -> Pleroma.Repo.delete(instance)
      end

      # Delete any pending ReachabilityWorker jobs for this domain
      Pleroma.Workers.ReachabilityWorker.delete_jobs_for_host(host)

      :ok
    end)
  end

  @impl true
  def timeout(_job), do: :timer.seconds(900)
end
