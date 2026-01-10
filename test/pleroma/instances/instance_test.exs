# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Instances.InstanceTest do
  alias Pleroma.Instances.Instance
  alias Pleroma.Repo

  use Oban.Testing, repo: Pleroma.Repo
  use Pleroma.DataCase

  import ExUnit.CaptureLog
  import Pleroma.Factory

  describe "set_reachable/1" do
    test "clears `unreachable_since` of existing matching Instance record having non-nil `unreachable_since`" do
      unreachable_since = NaiveDateTime.to_iso8601(NaiveDateTime.utc_now())
      instance = insert(:instance, unreachable_since: unreachable_since)

      assert {:ok, instance} = Instance.set_reachable(instance.host)
      refute instance.unreachable_since
    end

    test "keeps nil `unreachable_since` of existing matching Instance record having nil `unreachable_since`" do
      instance = insert(:instance, unreachable_since: nil)

      assert {:ok, instance} = Instance.set_reachable(instance.host)
      refute instance.unreachable_since
    end

    test "cancels all ReachabilityWorker jobs for the domain" do
      domain = "cancelme.example.org"
      insert(:instance, host: domain, unreachable_since: NaiveDateTime.utc_now())

      # Insert a ReachabilityWorker job for this domain, scheduled 5 minutes in the future
      scheduled_at = DateTime.add(DateTime.utc_now(), 300, :second)

      {:ok, job} =
        Pleroma.Workers.ReachabilityWorker.new(
          %{"domain" => domain, "phase" => "phase_1min", "attempt" => 1},
          scheduled_at: scheduled_at
        )
        |> Oban.insert()

      # Ensure the job is present
      job = Pleroma.Repo.get(Oban.Job, job.id)
      assert job

      # Call set_reachable, which should delete the job
      assert {:ok, _} = Instance.set_reachable(domain)

      # Reload the job and assert it is deleted
      job = Pleroma.Repo.get(Oban.Job, job.id)
      refute job
    end
  end

  describe "set_unreachable/1" do
    test "creates new record having `unreachable_since` to current time if record does not exist" do
      assert {:ok, instance} = Instance.set_unreachable("https://domain.com/path")

      instance = Repo.get(Instance, instance.id)
      assert instance.unreachable_since
      assert "domain.com" == instance.host
    end

    test "sets `unreachable_since` of existing record having nil `unreachable_since`" do
      instance = insert(:instance, unreachable_since: nil)
      refute instance.unreachable_since

      assert {:ok, _} = Instance.set_unreachable(instance.host)

      instance = Repo.get(Instance, instance.id)
      assert instance.unreachable_since
    end

    test "does NOT modify `unreachable_since` value of existing record in case it's present" do
      instance =
        insert(:instance, unreachable_since: NaiveDateTime.add(NaiveDateTime.utc_now(), -10))

      assert instance.unreachable_since
      initial_value = instance.unreachable_since

      assert {:ok, _} = Instance.set_unreachable(instance.host)

      instance = Repo.get(Instance, instance.id)
      assert initial_value == instance.unreachable_since
    end
  end

  describe "set_unreachable/2" do
    test "sets `unreachable_since` value of existing record in case it's newer than supplied value" do
      instance =
        insert(:instance, unreachable_since: NaiveDateTime.add(NaiveDateTime.utc_now(), -10))

      assert instance.unreachable_since

      past_value = NaiveDateTime.add(NaiveDateTime.utc_now(), -100)
      assert {:ok, _} = Instance.set_unreachable(instance.host, past_value)

      instance = Repo.get(Instance, instance.id)
      assert past_value == instance.unreachable_since
    end

    test "does NOT modify `unreachable_since` value of existing record in case it's equal to or older than supplied value" do
      instance =
        insert(:instance, unreachable_since: NaiveDateTime.add(NaiveDateTime.utc_now(), -10))

      assert instance.unreachable_since
      initial_value = instance.unreachable_since

      assert {:ok, _} = Instance.set_unreachable(instance.host, NaiveDateTime.utc_now())

      instance = Repo.get(Instance, instance.id)
      assert initial_value == instance.unreachable_since
    end
  end

  describe "get_or_update_favicon/1" do
    test "Scrapes favicon URLs" do
      Tesla.Mock.mock(fn %{url: "https://favicon.example.org/"} ->
        %Tesla.Env{
          status: 200,
          body: ~s[<html><head><link rel="icon" href="/favicon.png"></head></html>]
        }
      end)

      assert "https://favicon.example.org/favicon.png" ==
               Instance.get_or_update_favicon(URI.parse("https://favicon.example.org/"))
    end

    test "Returns nil on too long favicon URLs" do
      long_favicon_url =
        "https://Lorem.ipsum.dolor.sit.amet/consecteturadipiscingelit/Praesentpharetrapurusutaliquamtempus/Mauriseulaoreetarcu/atfacilisisorci/Nullamporttitor/nequesedfeugiatmollis/dolormagnaefficiturlorem/nonpretiumsapienorcieurisus/Nullamveleratsem/Maecenassedaccumsanexnam/favicon.png"

      Tesla.Mock.mock(fn %{url: "https://long-favicon.example.org/"} ->
        %Tesla.Env{
          status: 200,
          body:
            ~s[<html><head><link rel="icon" href="] <> long_favicon_url <> ~s["></head></html>]
        }
      end)

      assert capture_log(fn ->
               assert nil ==
                        Instance.get_or_update_favicon(
                          URI.parse("https://long-favicon.example.org/")
                        )
             end) =~
               "Instance.get_or_update_favicon(\"long-favicon.example.org\") error: %Postgrex.Error{"
    end

    test "Handles not getting a favicon URL properly" do
      Tesla.Mock.mock(fn %{url: "https://no-favicon.example.org/"} ->
        %Tesla.Env{
          status: 200,
          body: ~s[<html><head><h1>I wil look down and whisper "GNO.."</h1></head></html>]
        }
      end)

      refute capture_log(fn ->
               assert nil ==
                        Instance.get_or_update_favicon(
                          URI.parse("https://no-favicon.example.org/")
                        )
             end) =~ "Instance.scrape_favicon(\"https://no-favicon.example.org/\") error: "
    end

    test "Doesn't scrapes unreachable instances" do
      instance =
        insert(:instance,
          unreachable_since: NaiveDateTime.utc_now() |> NaiveDateTime.add(-:timer.hours(24))
        )

      url = "https://" <> instance.host

      assert capture_log(fn -> assert nil == Instance.get_or_update_favicon(URI.parse(url)) end) =~
               "Instance.scrape_favicon(\"#{url}\") ignored unreachable host"
    end
  end

  describe "get_or_update_metadata/1" do
    test "Scrapes Wildebeest NodeInfo" do
      Tesla.Mock.mock(fn
        %{url: "https://wildebeest.example.org/.well-known/nodeinfo"} ->
          %Tesla.Env{
            status: 200,
            body: File.read!("test/fixtures/wildebeest-well-known-nodeinfo.json")
          }

        %{url: "https://wildebeest.example.org/nodeinfo/2.1"} ->
          %Tesla.Env{
            status: 200,
            body: File.read!("test/fixtures/wildebeest-nodeinfo21.json")
          }
      end)

      expected = %{
        software_name: "wildebeest",
        software_repository: "https://github.com/cloudflare/wildebeest",
        software_version: "0.0.1"
      }

      assert expected ==
               Instance.get_or_update_metadata(URI.parse("https://wildebeest.example.org/"))

      expected = %Pleroma.Instances.Instance.Pleroma.Instances.Metadata{
        software_name: "wildebeest",
        software_repository: "https://github.com/cloudflare/wildebeest",
        software_version: "0.0.1"
      }

      assert expected ==
               Repo.get_by(Pleroma.Instances.Instance, %{host: "wildebeest.example.org"}).metadata
    end

    test "Scrapes Mastodon NodeInfo" do
      Tesla.Mock.mock(fn
        %{url: "https://mastodon.example.org/.well-known/nodeinfo"} ->
          %Tesla.Env{
            status: 200,
            body: File.read!("test/fixtures/mastodon-well-known-nodeinfo.json")
          }

        %{url: "https://mastodon.example.org/nodeinfo/2.0"} ->
          %Tesla.Env{
            status: 200,
            body: File.read!("test/fixtures/mastodon-nodeinfo20.json")
          }
      end)

      expected = %{
        software_name: "mastodon",
        software_version: "4.1.0"
      }

      assert expected ==
               Instance.get_or_update_metadata(URI.parse("https://mastodon.example.org/"))
    end
  end

  test "delete/1 schedules a job to delete the instance and users" do
    insert(:user, nickname: "mario@mushroom.kingdom", name: "Mario")

    {:ok, _job} = Instance.delete("mushroom.kingdom")

    assert_enqueued(
      worker: Pleroma.Workers.DeleteWorker,
      args: %{"op" => "delete_instance", "host" => "mushroom.kingdom"}
    )
  end

  describe "check_unreachable/1" do
    test "schedules a ReachabilityWorker job for the given domain" do
      domain = "test.example.com"

      # Call check_unreachable
      assert {:ok, _job} = Instance.check_unreachable(domain)

      # Verify that a ReachabilityWorker job was scheduled
      jobs = all_enqueued(worker: Pleroma.Workers.ReachabilityWorker)
      assert length(jobs) == 1
      [job] = jobs
      assert job.args["domain"] == domain
    end

    test "handles multiple calls for the same domain (uniqueness enforced)" do
      domain = "duplicate.example.com"

      assert {:ok, _job1} = Instance.check_unreachable(domain)

      # Second call for the same domain
      assert {:ok, %Oban.Job{conflict?: true}} = Instance.check_unreachable(domain)

      # Should only have one job due to uniqueness
      jobs = all_enqueued(worker: Pleroma.Workers.ReachabilityWorker)
      assert length(jobs) == 1
      [job] = jobs
      assert job.args["domain"] == domain
    end
  end
end
