# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Signature.API do
  @moduledoc """
  Behaviour for signing requests and producing HTTP Date headers.

  This is used to allow tests to replace the signing implementation with Mox.
  """

  @callback sign(user :: Pleroma.User.t(), headers :: map()) :: String.t()
  @callback signed_date() :: String.t()
end
