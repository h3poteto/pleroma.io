# Pleroma: A lightweight social networking server
# Copyright © 2017-2025 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Tesla.Middleware.EncodeUrl do
  @moduledoc """
  Middleware to encode URLs properly

  We must decode and then re-encode to ensure correct encoding.
  If we only encode it will re-encode each % as %25 causing a space
  already encoded as %20 to be %2520.

  Similar problem for query parameters which need spaces to be the + character
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(%Tesla.Env{url: url} = env, next, _) do
    url = Pleroma.Utils.URIEncoding.encode_url(url)

    env = %{env | url: url}

    case Tesla.run(env, next) do
      {:ok, env} -> {:ok, env}
      err -> err
    end
  end
end
