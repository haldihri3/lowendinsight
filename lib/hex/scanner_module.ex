# Copyright (C) 2020 by the Georgia Tech Research Institute (GTRI)
# This software may be modified and distributed under the terms of
# the BSD 3-Clause license. See the LICENSE file for details.

defmodule ScannerModule do
  @moduledoc """
  Scanner scans.
  """
  def scan(path) do
    cwd = File.cwd!()

    File.cd!(path)
    start_time = DateTime.utc_now()

    mixfile =
      File.read!("./mix.exs")
      |> Mixfile.parse()

    lib_map = Encoder.mixfile_map(mixfile)

    result_map =
      Enum.map(lib_map, fn {key, _value} ->
        query_hex(key)
      end)

    result = %{
      :state => :complete,
      :metadata => %{repo_count: length(result_map)},
      :report => %{:uuid => UUID.uuid1(), :repos => result_map}
    }

    result = AnalyzerModule.determine_risk_counts(result)

    end_time = DateTime.utc_now()
    duration = DateTime.diff(end_time, start_time)

    times = %{
      start_time: DateTime.to_iso8601(start_time),
      end_time: DateTime.to_iso8601(end_time),
      duration: duration
    }

    metadata = Map.put_new(result[:metadata], :times, times)
    result = result |> Map.put(:metadata, metadata)

    File.cd!(cwd)

    Poison.encode!(result, pretty: true)
    # Encoder.mixfile_json(mixfile)
  end

  defp query_hex(package) do
    HTTPoison.start()
    response = HTTPoison.get!("https://hex.pm/api/packages/#{package}")

    case response.status_code do
      404 ->
        "{\"error\":\"no package found in hex\"}"

      200 ->
        hex_package_links = Poison.decode!(response.body)["meta"]["links"]
        # Hex.pm API doesn't handle case stuff for us.
        hex_package_links =
          for {k, v} <- hex_package_links, into: %{}, do: {String.downcase(k), v}

        cond do
          Map.has_key?(hex_package_links, "github") ->
            {:ok, report} = AnalyzerModule.analyze(hex_package_links["github"], "mix.scan")

            report

          Map.has_key?(hex_package_links, "bitbucket") ->
            {:ok, report} = AnalyzerModule.analyze(hex_package_links["bitbucket"], "mix.scan")

            report

          Map.has_key?(hex_package_links, "gitlab") ->
            {:ok, report} = AnalyzerModule.analyze(hex_package_links["gitlab"], "mix.scan")

            report

          true ->
            "{\"error\":\"no source repo link available\"}"
        end
    end
  end
end