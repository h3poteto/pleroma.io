# Copyright 2012 Plataformatec
# Copyright 2021 The Elixir Team
# SPDX-License-Identifier: Apache-2.0

defmodule Pleroma.Backports do
  import File, only: [dir?: 1]

  # <https://github.com/elixir-lang/elixir/pull/14242>
  # To be removed when we require Elixir 1.19
  @doc """
  Tries to create the directory `path`.

  Missing parent directories are created. Returns `:ok` if successful, or
  `{:error, reason}` if an error occurs.

  Typical error reasons are:

    * `:eacces`  - missing search or write permissions for the parent
      directories of `path`
    * `:enospc`  - there is no space left on the device
    * `:enotdir` - a component of `path` is not a directory

  """
  @spec mkdir_p(Path.t()) :: :ok | {:error, File.posix() | :badarg}
  def mkdir_p(path) do
    do_mkdir_p(IO.chardata_to_string(path))
  end

  defp do_mkdir_p("/") do
    :ok
  end

  defp do_mkdir_p(path) do
    parent = Path.dirname(path)

    if parent == path do
      :ok
    else
      case do_mkdir_p(parent) do
        :ok ->
          case :file.make_dir(path) do
            {:error, :eexist} ->
              if dir?(path), do: :ok, else: {:error, :enotdir}

            other ->
              other
          end

        e ->
          e
      end
    end
  end

  @doc """
  Same as `mkdir_p/1`, but raises a `File.Error` exception in case of failure.
  Otherwise `:ok`.
  """
  @spec mkdir_p!(Path.t()) :: :ok
  def mkdir_p!(path) do
    case mkdir_p(path) do
      :ok ->
        :ok

      {:error, reason} ->
        raise File.Error,
          reason: reason,
          action: "make directory (with -p)",
          path: IO.chardata_to_string(path)
    end
  end
end
