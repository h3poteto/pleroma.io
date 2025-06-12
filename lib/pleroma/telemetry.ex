defmodule Pleroma.Telemetry do
  use Supervisor
  import Telemetry.Metrics
  import Ecto.Query

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000},
      {TelemetryMetricsPrometheus, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp metrics() do
    [
      # Phoenix Metrics
      counter("phoenix.endpoint.stop.count",
        tags: [:method, :route, :status_class],
        tag_values: &__MODULE__.phoenix_tag_values/1
      ),
      distribution("phoenix.endpoint.stop.duration",
        tags: [:method, :route, :status_class],
        tag_values: &__MODULE__.phoenix_tag_values/1,
        unit: {:native, :millisecond},
        reporter_options: [buckets: [10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000]]
      ),
      counter("phoenix.router_dispatch.exception.duration",
        tags: [:method, :route, :error_kind],
        tag_values: &__MODULE__.phoenix_exception_tag_values/1,
        unit: {:native, :millisecond}
      ),
      last_value("phoenix.endpoint.sessions.count"),

      # VM Metrics
      last_value("vm.memory.total", unit: :byte),
      last_value("vm.memory.processes", unit: :byte),
      last_value("vm.memory.system", unit: :byte),
      last_value("vm.memory.atom", unit: :byte),
      last_value("vm.memory.binary", unit: :byte),
      last_value("vm.memory.code", unit: :byte),
      last_value("vm.memory.ets", unit: :byte),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.total_run_queue_lengths.io"),
      last_value("vm.system_counts.process_count"),
      last_value("vm.system_counts.atom_count"),
      last_value("vm.system_counts.port_count"),

      # Oban Metrics
      # Refs: https://hexdocs.pm/oban/Oban.Telemetry.html#module-job-events
      # Refs: https://hexdocs.pm/telemetry_metrics_statsd/TelemetryMetricsStatsd.html#module-the-standard-statsd-formatter
      counter("oban.job.start.count",
        tag_values: &__MODULE__.oban_job_metadata/1,
        tags: [:queue, :worker, :state, :attempt]
      ),
      counter("oban.job.stop.count",
        tag_values: &__MODULE__.oban_job_metadata/1,
        tags: [:queue, :worker, :state, :attempt]
      ),
      counter("oban.job.exception.count",
        tag_values: &__MODULE__.oban_job_metadata/1,
        tags: [:queue, :worker, :state, :attempt]
      ),
      # Oban queue metrics
      last_value("oban.queue.length", tags: [:queue])
    ]
  end

  defp periodic_measurements do
    [
      {Pleroma.Telemetry, :count_oban_job_queue, []}
    ]
  end

  def phoenix_tag_values(metadata) do
    conn = metadata[:conn]

    %{
      method: conn.method,
      route: phoenix_route(conn),
      status_class: status_class(conn.status)
    }
  end

  def phoenix_exception_tag_values(metadata) do
    conn = metadata[:conn]

    %{
      method: conn.method,
      route: phoenix_route(conn),
      error_kind: metadata[:kind]
    }
  end

  defp phoenix_route(%{path_info: path_info}) when is_list(path_info) do
    "/" <> Enum.join(path_info, "/")
  end

  defp phoenix_route(%{request_path: request_path}) when is_binary(request_path) do
    request_path
  end

  defp phoenix_route(_conn), do: "unknown"

  defp status_class(status) when status >= 100 and status < 200, do: "1xx"
  defp status_class(status) when status >= 200 and status < 300, do: "2xx"
  defp status_class(status) when status >= 300 and status < 400, do: "3xx"
  defp status_class(status) when status >= 400 and status < 500, do: "4xx"
  defp status_class(status) when status >= 500 and status < 600, do: "5xx"
  defp status_class(_status), do: "unknown"

  def oban_job_metadata(%{
        job: %Oban.Job{queue: queue, attempt: attempt},
        state: state,
        worker: worker
      }) do
    %{queue: queue, state: state, worker: worker, attempt: attempt}
  end

  def oban_job_metadata(%{
        job: %Oban.Job{queue: queue, attempt: attempt, state: state},
        worker: worker
      }) do
    %{queue: queue, state: state, worker: worker, attempt: attempt}
  end

  def count_oban_job_queue do
    if Pleroma.Config.get(:env) != :test do
      query =
        Oban.Job |> select([j], %{queue: j.queue, count: count(j.id)}) |> group_by([j], j.queue)

      Oban
      |> Oban.config()
      |> Oban.Repo.all(query)
      |> Enum.each(fn %{count: count, queue: queue} ->
        :telemetry.execute([:oban, :queue], %{length: count}, %{queue: queue})
      end)
    end
  end
end
