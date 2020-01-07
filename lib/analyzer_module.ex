# Copyright (C) 2018 by the Georgia Tech Research Institute (GTRI)
# This software may be modified and distributed under the terms of
# the BSD 3-Clause license. See the LICENSE file for details.

defmodule AnalyzerModule do

  @moduledoc """
  Analyzer takes in a repo url and coordinates the analysis,
  returning a simple JSON report.
  """

  @doc """
  analyze/2: returns the LowEndInsight report as JSON

  Returns Map.

  ## Examples
    ```
    iex> {:ok, report} = AnalyzerModule.analyze("https://github.com/kitplummer/xmpp4rails", "iex")
    iex> _risk = report[:data][:risk]
    "critical"
    ```
  """
  @spec analyze(String.t() | list(), String.t()) :: tuple()
  def analyze(url, source) when is_binary(url) do
    start_time = DateTime.utc_now()

    url = URI.decode(url)

    try do

      if Helpers.count_forward_slashes(url) > 4 do
        raise ArgumentError, message: "Not a Git repo URL, is a subdirectory"
      end

      {:ok, repo} = GitModule.clone_repo(url)

      # Get unique contributors count
      {:ok, count} = GitModule.get_contributor_count(repo)

      # Get risk rating for count
      {:ok, count_risk} = RiskLogic.contributor_risk(count)

      # Get last commit in weeks
      {:ok, date} = GitModule.get_last_commit_date(repo)
      weeks = TimeHelper.get_commit_delta(date) |> TimeHelper.sec_to_weeks()

      # Get risk rating for last commit
      {:ok, delta_risk} = RiskLogic.commit_currency_risk(weeks)

      # Get risk rating for size of last commit

      {:ok, lines_percent, _file_percent} = GitModule.get_recent_changes(repo)
      {:ok, changes_risk} = RiskLogic.commit_change_size_risk(lines_percent)

      # get risk rating for number of contributors with over a certain percentage of commits

      {:ok, num_filtered_contributors, functional_contributors} =
        GitModule.get_functional_contributors(repo)

      {:ok, filtered_contributors_risk} =
        RiskLogic.functional_contributors_risk(num_filtered_contributors)

      GitModule.delete_repo(repo)

      # Generate report
      end_time = DateTime.utc_now()
      duration = DateTime.diff(end_time, start_time)

      # Return summary report as JSON
      # Workaround to allow `mix analyze` to work even that :application doesn't exist
      version = if :application.get_application != :undefined, do: elem(:application.get_key(:lowendinsight, :vsn), 1) |> List.to_string, else: ""
      report = %{
        header: %{
          start_time: DateTime.to_string(start_time),
          end_time: DateTime.to_string(end_time),
          duration: duration,
          uuid: UUID.uuid1(),
          source_client: source,
          version: version
        },
        data: %{
          config: Application.get_all_env(:lowendinsight),
          repo: url,
          contributor_count: count,
          contributor_risk: count_risk,
          commit_currency_weeks: weeks,
          commit_currency_risk: delta_risk,
          large_recent_commit_risk: changes_risk,
          recent_commit_size_in_percent_of_codebase: lines_percent,
          functional_contributors_risk: filtered_contributors_risk,
          functional_contributors: num_filtered_contributors,
          functional_contributor_names: functional_contributors
        }
      }
      {:ok, determine_toplevel_risk(report)}
    rescue
      MatchError ->
        {:ok, %{data: %{error: "Unable to analyze the repo (#{url}), is this a valid Git repo URL?", risk: "critical"}}}
      e in ArgumentError ->
        {:ok, %{data: %{error: "Unable to analyze the repo (#{url}). #{e.message}", risk: "N/A"}}}
    end
  end

  @doc """
  analyze/2: returns the LowEndInsight report as JSON for multiple_repos

  Returns Map.

  ## Examples
    ```
    iex> {:ok, report} = AnalyzerModule.analyze(["https://github.com/kitplummer/xmpp4rails","https://github.com/kitplummer/lita-cron"], "iex")
    iex> _count = report[:metadata][:repo_count]
    2
    ```
  """
  def analyze(urls, source) when is_list(urls) do
    start_time = DateTime.utc_now()
    ## Concurrency for parallelizing the analysis.  Turn the analyze/2 function into a worker.
    l = urls
      |> Task.async_stream(__MODULE__, :analyze, [source], [timeout: :infinity, max_concurrency: 10])
      |> Enum.map(fn {:ok, report} -> elem(report, 1) end)
    report = %{report: %{uuid: UUID.uuid1(), repos: l}, metadata: %{repo_count: length(l)}}

    report = determine_risk_counts(report)
    end_time = DateTime.utc_now()
    duration = DateTime.diff(end_time, start_time)
    times = %{start_time: DateTime.to_string(start_time), end_time: DateTime.to_string(end_time), duration: duration}
    metadata = Map.put_new(report[:metadata], :times, times)
    report = report |> Map.put(:metadata, metadata)
    {:ok, report}
  end

  defp determine_risk_counts(report) do
    count_map = report[:report][:repos]
        |> Enum.map(fn (repo) -> repo[:data][:risk] end)
        |> Enum.reduce(%{}, fn x, acc -> Map.update(acc, x, 1, &(&1 + 1)) end)
    metadata = Map.put_new(report[:metadata], :risk_counts, count_map)
    report |> Map.put(:metadata, metadata)
  end

  defp determine_toplevel_risk(report) do
    values = Map.values(report[:data])

    risk =
      cond do
        Enum.member?(values, "critical") -> "critical"
        Enum.member?(values, "high") -> "high"
        Enum.member?(values, "medium") -> "medium"
        true -> "low"
      end

    data = report[:data]
    data = Map.put_new(data, :risk, risk)
    report |> Map.put(:header, report[:header]) |> Map.put(:data, data)
  end
end
