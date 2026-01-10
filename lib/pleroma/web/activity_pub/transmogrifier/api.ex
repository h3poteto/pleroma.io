# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.Transmogrifier.API do
  @moduledoc """
  Behaviour for the subset of Transmogrifier used by Publisher.
  """

  @callback prepare_outgoing(map()) :: {:ok, map()} | {:error, term()}
end
