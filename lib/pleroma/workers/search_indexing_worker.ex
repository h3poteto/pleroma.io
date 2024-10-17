defmodule Pleroma.Workers.SearchIndexingWorker do
  use Pleroma.Workers.WorkerHelper, queue: "search_indexing"

  @impl Oban.Worker

  alias Pleroma.Config.Getting, as: Config

  def perform(%Job{args: %{"op" => "add_to_index", "activity" => activity_id}}) do
    activity = Pleroma.Activity.get_by_id_with_object(activity_id)

    search_module = Config.get([Pleroma.Search, :module])

    search_module.add_to_index(activity)
  end

  def perform(%Job{args: %{"op" => "remove_from_index", "object" => object_id}}) do
    object = Pleroma.Object.get_by_id(object_id)

    search_module = Config.get([Pleroma.Search, :module])

    search_module.remove_from_index(object)
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(5)
end
