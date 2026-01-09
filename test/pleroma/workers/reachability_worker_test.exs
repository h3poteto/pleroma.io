# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Workers.ReachabilityWorkerTest do
  use Pleroma.DataCase, async: true
  use Oban.Testing, repo: Pleroma.Repo

  import Mock

  alias Pleroma.Tests.ObanHelpers
  alias Pleroma.Workers.ReachabilityWorker

  setup do
    ObanHelpers.wipe_all()
    :ok
  end

  describe "progressive backoff phases" do
    test "starts with phase_1min and progresses through phases on failure" do
      domain = "example.com"

      with_mocks([
        {Pleroma.HTTP, [], [get: fn _ -> {:error, :timeout} end]},
        {Pleroma.Instances, [], [set_reachable: fn _ -> :ok end]}
      ]) do
        # Start with phase_1min
        job = %Oban.Job{
          args: %{"domain" => domain, "phase" => "phase_1min", "attempt" => 1}
        }

        # First attempt fails
        assert {:error, :timeout} = ReachabilityWorker.perform(job)

        # Should schedule retry for phase_1min (attempt 2)
        retry_jobs = all_enqueued(worker: ReachabilityWorker)
        assert length(retry_jobs) == 1
        [retry_job] = retry_jobs
        assert retry_job.args["phase"] == "phase_1min"
        assert retry_job.args["attempt"] == 2

        # Clear jobs and simulate second attempt failure
        ObanHelpers.wipe_all()

        retry_job = %Oban.Job{
          args: %{"domain" => domain, "phase" => "phase_1min", "attempt" => 2}
        }

        assert {:error, :timeout} = ReachabilityWorker.perform(retry_job)

        # Should schedule retry for phase_1min (attempt 3)
        retry_jobs = all_enqueued(worker: ReachabilityWorker)
        assert length(retry_jobs) == 1
        [retry_job] = retry_jobs
        assert retry_job.args["phase"] == "phase_1min"
        assert retry_job.args["attempt"] == 3

        # Clear jobs and simulate third attempt failure (final attempt for phase_1min)
        ObanHelpers.wipe_all()

        retry_job = %Oban.Job{
          args: %{"domain" => domain, "phase" => "phase_1min", "attempt" => 3}
        }

        assert {:error, :timeout} = ReachabilityWorker.perform(retry_job)

        # Should schedule retry for phase_1min (attempt 4)
        retry_jobs = all_enqueued(worker: ReachabilityWorker)
        assert length(retry_jobs) == 1
        [retry_job] = retry_jobs
        assert retry_job.args["phase"] == "phase_1min"
        assert retry_job.args["attempt"] == 4

        # Clear jobs and simulate fourth attempt failure (final attempt for phase_1min)
        ObanHelpers.wipe_all()

        retry_job = %Oban.Job{
          args: %{"domain" => domain, "phase" => "phase_1min", "attempt" => 4}
        }

        assert {:error, :timeout} = ReachabilityWorker.perform(retry_job)

        # Should schedule next phase (phase_15min)
        next_phase_jobs = all_enqueued(worker: ReachabilityWorker)
        assert length(next_phase_jobs) == 1
        [next_phase_job] = next_phase_jobs
        assert next_phase_job.args["phase"] == "phase_15min"
        assert next_phase_job.args["attempt"] == 1
      end
    end

    test "progresses through all phases correctly" do
      domain = "example.com"

      with_mocks([
        {Pleroma.HTTP, [], [get: fn _ -> {:error, :timeout} end]},
        {Pleroma.Instances, [], [set_reachable: fn _ -> :ok end]}
      ]) do
        # Simulate all phases failing
        phases = ["phase_1min", "phase_15min", "phase_1hour", "phase_8hour", "phase_24hour"]

        Enum.each(phases, fn phase ->
          {_interval, max_attempts, next_phase} = get_phase_config(phase)

          # Simulate all attempts failing for this phase
          Enum.each(1..max_attempts, fn attempt ->
            job = %Oban.Job{args: %{"domain" => domain, "phase" => phase, "attempt" => attempt}}
            assert {:error, :timeout} = ReachabilityWorker.perform(job)

            if attempt < max_attempts do
              # Should schedule retry for same phase
              retry_jobs = all_enqueued(worker: ReachabilityWorker)
              assert length(retry_jobs) == 1
              [retry_job] = retry_jobs
              assert retry_job.args["phase"] == phase
              assert retry_job.args["attempt"] == attempt + 1
              ObanHelpers.wipe_all()
            else
              # Should schedule next phase (except for final phase)
              if next_phase != "final" do
                next_phase_jobs = all_enqueued(worker: ReachabilityWorker)
                assert length(next_phase_jobs) == 1
                [next_phase_job] = next_phase_jobs
                assert next_phase_job.args["phase"] == next_phase
                assert next_phase_job.args["attempt"] == 1
                ObanHelpers.wipe_all()
              else
                # Final phase - no more jobs should be scheduled
                next_phase_jobs = all_enqueued(worker: ReachabilityWorker)
                assert length(next_phase_jobs) == 0
              end
            end
          end)
        end)
      end
    end

    test "succeeds and stops progression when instance becomes reachable" do
      domain = "example.com"

      with_mocks([
        {Pleroma.HTTP, [], [get: fn _ -> {:ok, %{status: 200}} end]},
        {Pleroma.Instances, [], [set_reachable: fn _ -> :ok end]}
      ]) do
        job = %Oban.Job{args: %{"domain" => domain, "phase" => "phase_1hour", "attempt" => 2}}

        # Should succeed and not schedule any more jobs
        assert :ok = ReachabilityWorker.perform(job)

        # Verify set_reachable was called
        assert_called(Pleroma.Instances.set_reachable("https://#{domain}"))

        # No more jobs should be scheduled
        next_jobs = all_enqueued(worker: ReachabilityWorker)
        assert length(next_jobs) == 0
      end
    end

    test "enforces uniqueness per domain using Oban's conflict detection" do
      domain = "example.com"

      # Insert first job for the domain
      job1 =
        %{
          "domain" => domain,
          "phase" => "phase_1min",
          "attempt" => 1
        }
        |> ReachabilityWorker.new()
        |> Oban.insert()

      assert {:ok, _} = job1

      # Try to insert a second job for the same domain with different phase/attempt
      job2 =
        %{
          "domain" => domain,
          "phase" => "phase_15min",
          "attempt" => 1
        }
        |> ReachabilityWorker.new()
        |> Oban.insert()

      # Should fail due to uniqueness constraint (conflict)
      assert {:ok, %Oban.Job{conflict?: true}} = job2

      # Verify only one job exists for this domain
      jobs = all_enqueued(worker: ReachabilityWorker)
      assert length(jobs) == 1
      [existing_job] = jobs
      assert existing_job.args["domain"] == domain
      assert existing_job.args["phase"] == "phase_1min"
    end

    test "handles new jobs with only domain argument and transitions them to the first phase" do
      domain = "legacy.example.com"

      with_mocks([
        {Pleroma.Instances, [], [set_reachable: fn _ -> :ok end]}
      ]) do
        # Create a job with only domain (legacy format)
        job = %Oban.Job{
          args: %{"domain" => domain}
        }

        # Should reschedule with phase_1min and attempt 1
        assert :ok = ReachabilityWorker.perform(job)

        # Check that a new job was scheduled with the correct format
        scheduled_jobs = all_enqueued(worker: ReachabilityWorker)
        assert length(scheduled_jobs) == 1
        [scheduled_job] = scheduled_jobs
        assert scheduled_job.args["domain"] == domain
        assert scheduled_job.args["phase"] == "phase_1min"
        assert scheduled_job.args["attempt"] == 1
      end
    end
  end

  defp get_phase_config("phase_1min"), do: {1, 4, "phase_15min"}
  defp get_phase_config("phase_15min"), do: {15, 4, "phase_1hour"}
  defp get_phase_config("phase_1hour"), do: {60, 4, "phase_8hour"}
  defp get_phase_config("phase_8hour"), do: {480, 4, "phase_24hour"}
  defp get_phase_config("phase_24hour"), do: {1440, 4, "final"}
  defp get_phase_config("final"), do: {nil, 0, nil}
end
