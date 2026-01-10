# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Language.LanguageDetectorTest do
  use Pleroma.DataCase, async: true

  alias Pleroma.Language.LanguageDetector
  alias Pleroma.Language.LanguageDetectorMock
  alias Pleroma.StaticStubbedConfigMock

  import Mox

  setup do
    # Stub the StaticStubbedConfigMock to return our mock for the provider
    StaticStubbedConfigMock
    |> stub(:get, fn
      [Pleroma.Language.LanguageDetector, :provider] -> LanguageDetectorMock
      _other -> nil
    end)

    # Stub the LanguageDetectorMock with default implementations
    LanguageDetectorMock
    |> stub(:missing_dependencies, fn -> [] end)
    |> stub(:configured?, fn -> true end)

    :ok
  end

  test "it detects text language" do
    LanguageDetectorMock
    |> expect(:detect, fn _text -> "fr" end)

    detected_language = LanguageDetector.detect("Je viens d'atterrir en Tchéquie.")

    assert detected_language == "fr"
  end

  test "it returns nil if text is not long enough" do
    # No need to set expectations as the word count check happens before the provider is called

    detected_language = LanguageDetector.detect("it returns nil")

    assert detected_language == nil
  end

  test "it returns nil if no provider specified" do
    # Override the stub to return nil for the provider
    StaticStubbedConfigMock
    |> expect(:get, fn [Pleroma.Language.LanguageDetector, :provider] -> nil end)

    detected_language = LanguageDetector.detect("this should also return nil")

    assert detected_language == nil
  end
end
