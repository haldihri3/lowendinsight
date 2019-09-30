defmodule GitHelper do

    @doc """
        parse_diff/1: returns the relevant information contained in the last array positino of a diff array 
    """
    def parse_diff(list) do
        last = List.last(list)
        last_trimmed = String.trim(last)
        commit_info = String.split(last_trimmed, ", ")
        file_string = Enum.at(commit_info, 0)
        if file_string == nil do
            {:ok, 0, 0, 0}
        else
            insertion_string = Enum.at(commit_info, 1)
            if insertion_string == nil do
                [file_num | _tail] = String.split(file_string, " ")
                {:ok, String.to_integer(file_num), 0, 0}
            else
                deletion_string = Enum.at(commit_info, 2)
                if deletion_string == nil do
                    [file_num | _tail] = String.split(file_string, " ")
                    [insertion_num | _tail] = String.split(insertion_string, " ")
                    {:ok, String.to_integer(file_num), String.to_integer(insertion_num), 0}
                else
                    [file_num | _tail] = String.split(file_string, " ")
                    [insertion_num | _tail] = String.split(insertion_string, " ")
                    [deletion_num | _tail] = String.split(deletion_string, " ")
                    {:ok, String.to_integer(file_num), String.to_integer(insertion_num), String.to_integer(deletion_num)}
                end
            end
        end
    end

    @doc """
        get_avg_tag_commit_tim_diff/1: return the average time between commits within each subarray representing a tag 
    """
    def get_avg_tag_commit_time_diff(list) do
        get_avg_tag_commit_time_diff(list, [])
    end

    @doc """
        get_total_tag_commit_time_diff/1: return the total time between commits within each subarray representing a tag 
    """
    def get_total_tag_commit_time_diff(list) do
        get_total_tag_commit_time_diff(list, [])
    end

    @doc """
        split_commits_by_tag/1: returns a list with sublists arranged by tag
    """
    def split_commits_by_tag(list) do
        split_commits_by_tag(list, [])
    end

    @doc """
        get_contributor_counts/1: Gets the number of contributions belonging to each author and return a map of %{name => number}
    """
    def get_contributor_counts(list) do
        get_contributor_counts(list, %{})
    end

    def get_filtered_contributor_count(map, total) do
        filter = Application.fetch_env!(:lowendinsight, :functional_contributors_filter_percent)
        filtered_list = Enum.filter(map, fn {_key, value} -> (value / total) >= filter end)
        length = Kernel.length(filtered_list)
        {:ok, length, filtered_list}
    end

    defp split_commits_by_tag([], current) do
        {:ok, current}
    end

    defp split_commits_by_tag([first | rest], []) do
        split_commits_by_tag(rest, [[first]])
    end

    defp split_commits_by_tag([first | rest], current) do
        [head | _tail] = first
        if String.contains?(head, "tag") do
            new_current = [[first] | current]
            split_commits_by_tag(rest, new_current)
        else
            [current_head | current_tail] = current
            new_current = [[first | current_head] | current_tail]
            split_commits_by_tag(rest, new_current)
        end
    end

    defp get_total_tag_commit_time_diff([first | tail], accumulator) do
        {:ok, time} = TimeHelper.sum_ts_diff(first)
        ret = [time | accumulator]
        get_total_tag_commit_time_diff(tail, ret)
    end

    defp get_total_tag_commit_time_diff([], accumulator) do
        {:ok, accumulator}
    end

    defp get_avg_tag_commit_time_diff([first | tail], accumulator) do
        {:ok, time} = TimeHelper.sum_ts_diff(first)
        ret = [(time / Kernel.length(first)) | accumulator]
        get_avg_tag_commit_time_diff(tail, ret)
    end

    defp get_avg_tag_commit_time_diff([], accumulator) do
        {:ok, accumulator}
    end

    defp get_contributor_counts([head | tail], accumulator) do
        if head == "" do
            get_contributor_counts(tail, accumulator)
        else
            maybe_new_key = Map.put_new(accumulator, String.trim(head), 0)
            {_num, new_value} = Map.get_and_update(maybe_new_key, head, fn current_value -> {current_value, current_value + 1} end)
            get_contributor_counts(tail, new_value)
        end
    end

    defp get_contributor_counts([], accumulator) do
        {:ok, accumulator}
    end
end