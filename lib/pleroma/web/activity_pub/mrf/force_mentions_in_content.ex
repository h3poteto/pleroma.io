# Pleroma: A lightweight social networking server
# Copyright © 2017-2023 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.MRF.ForceMentionsInContent do
  require Pleroma.Constants

  alias Pleroma.Formatter
  alias Pleroma.Object
  alias Pleroma.User

  @behaviour Pleroma.Web.ActivityPub.MRF.Policy

  @impl true
  def history_awareness, do: :auto

  defp do_extract({:a, attrs, _}, acc) do
    if Enum.find(attrs, fn {name, value} ->
         name == "class" && value in ["mention", "u-url mention", "mention u-url"]
       end) do
      href = Enum.find(attrs, fn {name, _} -> name == "href" end) |> elem(1)
      acc ++ [href]
    else
      acc
    end
  end

  defp do_extract({_, _, children}, acc) do
    do_extract(children, acc)
  end

  defp do_extract(nodes, acc) when is_list(nodes) do
    Enum.reduce(nodes, acc, fn node, acc -> do_extract(node, acc) end)
  end

  defp do_extract(_, acc), do: acc

  defp extract_mention_uris_from_content(content) do
    {:ok, tree} = :fast_html.decode(content, format: [:html_atoms])
    do_extract(tree, [])
  end

  defp get_replied_to_user(%{"inReplyTo" => in_reply_to}) do
    case Object.normalize(in_reply_to, fetch: false) do
      %Object{data: %{"actor" => actor}} -> User.get_cached_by_ap_id(actor)
      _ -> nil
    end
  end

  defp get_replied_to_user(_object), do: nil

  # Ensure the replied-to user is sorted to the left
  defp sort_replied_user([%User{id: user_id} | _] = users, %User{id: user_id}), do: users

  defp sort_replied_user(users, %User{id: user_id} = user) do
    if Enum.find(users, fn u -> u.id == user_id end) do
      users = Enum.reject(users, fn u -> u.id == user_id end)
      [user | users]
    else
      users
    end
  end

  defp sort_replied_user(users, _), do: users

  # Drop constants and the actor's own AP ID
  defp clean_recipients(recipients, object) do
    Enum.reject(recipients, fn ap_id ->
      ap_id in [
        object["object"]["actor"],
        Pleroma.Constants.as_public(),
        Pleroma.Web.ActivityPub.Utils.as_local_public()
      ]
    end)
  end

  @impl true
  def filter(
        %{
          "type" => type,
          "object" => %{"type" => "Note", "to" => to, "inReplyTo" => in_reply_to}
        } = object
      )
      when type in ["Create", "Update"] and is_list(to) and is_binary(in_reply_to) do
    # image-only posts from pleroma apparently reach this MRF without the content field
    content = object["object"]["content"] || ""

    # Get the replied-to user for sorting
    replied_to_user = get_replied_to_user(object["object"])

    mention_users =
      to
      |> clean_recipients(object)
      |> Enum.map(&User.get_cached_by_ap_id/1)
      |> Enum.reject(&is_nil/1)
      |> sort_replied_user(replied_to_user)

    explicitly_mentioned_uris =
      extract_mention_uris_from_content(content)
      |> MapSet.new()

    added_mentions =
      Enum.reduce(mention_users, "", fn %User{ap_id: ap_id, uri: uri} = user, acc ->
        if MapSet.disjoint?(MapSet.new([ap_id, uri]), explicitly_mentioned_uris) do
          acc <> Formatter.mention_from_user(user, %{mentions_format: :compact}) <> " "
        else
          acc
        end
      end)

    recipients_inline =
      if added_mentions != "",
        do: "<span class=\"recipients-inline\">#{added_mentions}</span>",
        else: ""

    content =
      cond do
        # For Markdown posts, insert the mentions inside the first <p> tag
        recipients_inline != "" && String.starts_with?(content, "<p>") ->
          "<p>" <> recipients_inline <> String.trim_leading(content, "<p>")

        recipients_inline != "" ->
          recipients_inline <> content

        true ->
          content
      end

    {:ok, put_in(object["object"]["content"], content)}
  end

  @impl true
  def filter(object), do: {:ok, object}

  @impl true
  def describe, do: {:ok, %{}}
end
