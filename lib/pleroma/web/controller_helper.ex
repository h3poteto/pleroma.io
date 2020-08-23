# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ControllerHelper do
  use Pleroma.Web, :controller

  alias Pleroma.Pagination

  # As in Mastodon API, per https://api.rubyonrails.org/classes/ActiveModel/Type/Boolean.html
  @falsy_param_values [false, 0, "0", "f", "F", "false", "False", "FALSE", "off", "OFF"]
  def truthy_param?(blank_value) when blank_value in [nil, ""], do: nil
  def truthy_param?(value), do: value not in @falsy_param_values

  def json_response(conn, status, json) do
    conn
    |> put_status(status)
    |> json(json)
  end

  @spec fetch_integer_param(map(), String.t(), integer() | nil) :: integer() | nil
  def fetch_integer_param(params, name, default \\ nil) do
    params
    |> Map.get(name, default)
    |> param_to_integer(default)
  end

  defp param_to_integer(val, _) when is_integer(val), do: val

  defp param_to_integer(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {res, _} -> res
      _ -> default
    end
  end

  defp param_to_integer(_, default), do: default

  def add_link_headers(conn, activities, extra_params \\ %{})

  def add_link_headers(%{assigns: %{skip_link_headers: true}} = conn, _activities, _extra_params),
    do: conn

  def add_link_headers(conn, activities, extra_params) do
    case get_pagination_fields(conn, activities, extra_params) do
      %{"next" => next_url, "prev" => prev_url} ->
        put_resp_header(conn, "link", "<#{next_url}>; rel=\"next\", <#{prev_url}>; rel=\"prev\"")

      _ ->
        conn
    end
  end

  def get_pagination_fields(conn, activities, extra_params \\ %{}) do
    case List.last(activities) do
      %{id: max_id} ->
        params =
          conn.params
          |> Map.drop(Map.keys(conn.path_params))
          |> Map.merge(extra_params)
          |> Map.drop(Pagination.page_keys() -- ["limit", "order"])

        min_id =
          activities
          |> List.first()
          |> Map.get(:id)

        fields = %{
          "next" => current_url(conn, Map.put(params, :max_id, max_id)),
          "prev" => current_url(conn, Map.put(params, :min_id, min_id))
        }

        #  Generating an `id` without already present pagination keys would
        # need a query-restriction with an `q.id >= ^id` or `q.id <= ^id`
        # instead of the `q.id > ^min_id` and `q.id < ^max_id`.
        #  This is because we only have ids present inside of the page, while
        # `min_id`, `since_id` and `max_id` requires to know one outside of it.
        if Map.take(conn.params, Pagination.page_keys() -- ["limit", "order"]) != [] do
          Map.put(fields, "id", current_url(conn, conn.params))
        else
          fields
        end

      _ ->
        %{}
    end
  end

  def assign_account_by_id(%{params: %{"id" => id}} = conn, _) do
    case Pleroma.User.get_cached_by_id(id) do
      %Pleroma.User{} = account -> assign(conn, :account, account)
      nil -> Pleroma.Web.MastodonAPI.FallbackController.call(conn, {:error, :not_found}) |> halt()
    end
  end

  def try_render(conn, target, params) when is_binary(target) do
    case render(conn, target, params) do
      nil -> render_error(conn, :not_implemented, "Can't display this activity")
      res -> res
    end
  end

  def try_render(conn, _, _) do
    render_error(conn, :not_implemented, "Can't display this activity")
  end

  @spec put_in_if_exist(map(), atom() | String.t(), any) :: map()
  def put_in_if_exist(map, _key, nil), do: map
  def put_in_if_exist(map, key, value), do: put_in(map, key, value)
end
