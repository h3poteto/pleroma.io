# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Instances do
  @moduledoc "Instances context."

  alias Pleroma.Instances.Instance

  defdelegate filter_reachable(urls_or_hosts), to: Instance

  defdelegate reachable?(url_or_host), to: Instance

  defdelegate set_reachable(url_or_host), to: Instance

  defdelegate set_unreachable(url_or_host, unreachable_since \\ nil), to: Instance

  defdelegate get_unreachable, to: Instance

  def host(url_or_host) when is_binary(url_or_host) do
    if url_or_host =~ ~r/^http/i do
      URI.parse(url_or_host).host
    else
      url_or_host
    end
  end

  @doc "Schedules reachability checks for all unreachable instances"
  def check_all_unreachable do
    get_unreachable()
    |> Enum.each(fn {domain, _} ->
      Pleroma.Workers.ReachabilityWorker.new(%{"domain" => domain})
      |> Oban.insert()
    end)
  end

  @doc "Deletes all users and activities for unreachable instances"
  def delete_all_unreachable do
    get_unreachable()
    |> Enum.each(fn {domain, _} ->
      Instance.delete(domain)
    end)
  end
end
