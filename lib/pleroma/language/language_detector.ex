# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Language.LanguageDetector do
  import Pleroma.EctoType.ActivityPub.ObjectValidators.LanguageCode,
    only: [good_locale_code?: 1]

  @words_threshold 4
  @config_impl Application.compile_env(:pleroma, [__MODULE__, :config_impl], Pleroma.Config)

  def configured? do
    provider = get_provider()

    !!provider and provider.configured?()
  end

  def missing_dependencies do
    provider = get_provider()

    if provider do
      provider.missing_dependencies()
    else
      []
    end
  end

  # Strip tags from text, etc.
  defp prepare_text(text) do
    text
    |> Floki.parse_fragment!()
    |> Floki.filter_out(
      ".h-card, .mention, .hashtag, .u-url, .quote-inline, .recipients-inline, code, pre"
    )
    |> Floki.text()
  end

  def detect(text) do
    provider = get_provider()

    text = prepare_text(text)
    word_count = text |> String.split(~r/\s+/) |> Enum.count()

    if word_count < @words_threshold or !provider or !provider.configured?() do
      nil
    else
      with language <- provider.detect(text),
           true <- good_locale_code?(language) do
        language
      else
        _ -> nil
      end
    end
  end

  defp get_provider do
    @config_impl.get([__MODULE__, :provider])
  end
end
