# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.MastodonAPI.SearchController do
  use Pleroma.Web, :controller

  alias Pleroma.Hashtag
  alias Pleroma.Repo
  alias Pleroma.User
  alias Pleroma.Web.ControllerHelper
  alias Pleroma.Web.Endpoint
  alias Pleroma.Web.MastodonAPI.AccountView
  alias Pleroma.Web.MastodonAPI.StatusView
  alias Pleroma.Web.Plugs.OAuthScopesPlug
  alias Pleroma.Web.Plugs.RateLimiter

  require Logger

  @search_limit 40

  plug(Pleroma.Web.ApiSpec.CastAndValidate, replace_params: false)

  # Note: Mastodon doesn't allow unauthenticated access (requires read:accounts / read:search)
  plug(OAuthScopesPlug, %{scopes: ["read:search"], fallback: :proceed_unauthenticated})

  # Note: on private instances auth is required (EnsurePublicOrAuthenticatedPlug is not skipped)

  plug(RateLimiter, [name: :search] when action in [:search, :search2, :account_search])

  defdelegate open_api_operation(action), to: Pleroma.Web.ApiSpec.SearchOperation

  def account_search(
        %{assigns: %{user: user}, private: %{open_api_spex: %{params: %{q: query} = params}}} =
          conn,
        _
      ) do
    accounts = User.search(query, search_options(params, user))

    conn
    |> put_view(AccountView)
    |> render("index.json",
      users: accounts,
      for: user,
      as: :user
    )
  end

  def search2(conn, params), do: do_search(:v2, conn, params)
  def search(conn, params), do: do_search(:v1, conn, params)

  defp do_search(
         version,
         %{assigns: %{user: user}, private: %{open_api_spex: %{params: %{q: query} = params}}} =
           conn,
         _
       ) do
    query = String.trim(query)
    options = search_options(params, user)
    timeout = Keyword.get(Repo.config(), :timeout, 15_000)
    default_values = %{"statuses" => [], "accounts" => [], "hashtags" => []}

    result =
      default_values
      |> Enum.map(fn {resource, default_value} ->
        if params[:type] in [nil, resource] do
          {resource, fn -> resource_search(version, resource, query, options) end}
        else
          {resource, fn -> default_value end}
        end
      end)
      |> Task.async_stream(fn {resource, f} -> {resource, with_fallback(f)} end,
        timeout: timeout,
        on_timeout: :kill_task
      )
      |> Enum.reduce(default_values, fn
        {:ok, {resource, result}}, acc ->
          Map.put(acc, resource, result)

        _error, acc ->
          acc
      end)

    json(conn, result)
  end

  defp search_options(params, user) do
    [
      resolve: params[:resolve],
      following: params[:following],
      limit: min(params[:limit], @search_limit),
      offset: params[:offset],
      type: params[:type],
      capabilities: params[:capabilities],
      author: get_author(params),
      embed_relationships: ControllerHelper.embed_relationships?(params),
      for_user: user
    ]
    |> Enum.filter(&elem(&1, 1))
  end

  defp resource_search(_, "accounts", query, options) do
    accounts = with_fallback(fn -> User.search(query, options) end)

    AccountView.render("index.json",
      users: accounts,
      for: options[:for_user],
      embed_relationships: options[:embed_relationships]
    )
  end

  defp resource_search(_, "statuses", query, options) do
    statuses = with_fallback(fn -> Pleroma.Search.search(query, options) end)

    StatusView.render("index.json",
      activities: statuses,
      for: options[:for_user],
      as: :activity
    )
  end

  defp resource_search(:v2, "hashtags", query, options) do
    tags_path = Endpoint.url() <> "/tag/"

    Hashtag.search(query, options)
    |> Enum.map(fn tag ->
      %{name: tag, url: tags_path <> tag}
    end)
  end

  defp resource_search(:v1, "hashtags", query, options) do
    Hashtag.search(query, options)
  end

  defp with_fallback(f, fallback \\ []) do
    try do
      f.()
    rescue
      error ->
        Logger.error(Exception.format(:error, error, __STACKTRACE__))
        fallback
    end
  end

  defp get_author(%{account_id: account_id}) when is_binary(account_id),
    do: User.get_cached_by_id(account_id)

  defp get_author(_params), do: nil
end
