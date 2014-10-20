## Copyright (C) 2014 Karl Wette
##
## This program is free software; you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation; either version 2 of the License, or
## (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with with program; see the file COPYING. If not, write to the
## Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
## MA  02111-1307  USA

## Merge results from a Condor DAG.
## Usage:
##   mergeCondorResults("opt", val, ...)
## Options:
##   "dag_name":       Name of Condor DAG, used to name DAG submit file.
##                     Merged results are saved as 'dag_name' + _merged.bin.gz
##   "merge_function": Function(s) used to merge results from two Condor
##                     jobs with the same arguments, as determined by
##                     the DAG job name 'vars' field. Syntax is:
##                       merged_res = merge_function(merged_res, res, args)
##                     where 'res' are to be merged into 'merged_res', and
##                     'args' are the arguments passed to the job.
##                     One function per element of job 'results' must be given.
##   "norm_function":  If given, function(s) used to normalise merged results
##                     after all Condor jobs have been processed. Syntax is:
##                       merged_res = norm_function(merged_res, n)
##                     where 'n' is the number of merged Condor jobs
##                     One function per element of job 'results' must be given.

function mergeCondorResults(varargin)

  ## parse options
  parseOptions(varargin,
               {"dag_name", "char"},
               {"merge_function", "function,vector"},
               {"norm_function", "function,vector", []},
               []);
  if length(merge_function) == 1
    merge_function = {merge_function};
  else
    assert(iscell(merge_function), "%s: 'merge_function' must either be scalar or a cell array", funcName);
  endif
  if length(norm_function) == 0
    norm_function = {};
  elseif length(norm_function) == 1
    norm_function = {norm_function};
  else
    assert(iscell(norm_function), "%s: 'norm_function' must either be empty, scalar or a cell array", funcName);
  endif

  ## load job node data
  dag_nodes_file = strcat(dag_name, "_nodes.bin.gz");
  printf("%s: loading '%s' ...", funcName, dag_nodes_file);
  load(dag_nodes_file);
  assert(isstruct(job_nodes), "%s: 'job_nodes' is not a struct", funcName);
  printf(" done\n");

  ## load merged job results file if it already exists
  dag_merged_file = strcat(dag_name, "_merged.bin.gz");
  if exist(dag_merged_file, "file")
    printf("%s: loading '%s' ...", funcName, dag_merged_file);
    load(dag_merged_file);
    assert(isstruct(merged), "%s: 'merged' is not a struct", funcName);
    printf(" done\n");

    ## return if all jobs have been merged
    if !isfield(merged, "jobs_to_merge")
      printf("%s: skipping DAG '%s'; no more jobs to merge\n", funcName, dag_name);
      return;
    endif

  else

    ## otherwise create merged struct
    merged = struct;
    merged.dag_name = dag_name;
    merged.cpu_time = [];
    merged.wall_time = [];
    merged.arguments = {};
    merged.results = {};
    merged.jobs_per_result = [];

    ## need to merge all jobs
    merged.jobs_to_merge = 1:length(job_nodes);

  endif

  ## setup for job merging
  prog = [];
  jobs_to_merge = merged.jobs_to_merge;
  job_merged_count = 0;
  job_merged_total = length(jobs_to_merge);
  job_save_period = ceil(max(10, min(0.1*job_merged_total, 100)));
  argument_strs = cellfun(@(x) stringify(x), merged.arguments, "UniformOutput", false);
  
  ## iterate over jobs which need to be merged
  for n = jobs_to_merge

    ## load job node results, skipping missing files
    node_result_file = glob(fullfile(job_nodes(n).dir, "stdres.*"));
    if size(node_result_file, 1) < 1
      printf("%s: skipping job node '%s'; no result file\n", funcName, job_nodes(n).name);
      --job_merged_total;
      continue
    elseif size(node_result_file, 1) > 1
      error("%s: job node directory '%s' contains multiple result files", funcName, job_nodes(n).dir);
    endif
    try
      node_results = load(node_result_file{1});
    catch
      printf("%s: skipping job node '%s'; could not open result file\n", funcName, job_nodes(n).name);
      continue
    end_try_catch
    assert(isfield(node_results, "arguments"), "%s: job node '%s' does not have field 'arguments'", funcName, job_nodes(n).name);
    assert(isfield(node_results, "results"), "%s: job node '%s' does not have field 'results'", funcName, job_nodes(n).name);
    assert(isfield(node_results, "cpu_time"), "%s: job node '%s' does not have field 'cpu_time'", funcName, job_nodes(n).name);
    assert(isfield(node_results, "wall_time"), "%s: job node '%s' does not have field 'wall_time'", funcName, job_nodes(n).name);
    assert(length(merge_function) == length(node_results.results),
           "%s: length of 'merge_function' does not match number of job node '%s' results", funcName, job_nodes(n).name);
    if !isempty(norm_function)
      assert(length(norm_function) == length(node_results.results),
             "%s: length of 'norm_function' does not match number of job node '%s' results", funcName, job_nodes(n).name);
    endif

    ## add to list of CPU and wall times
    merged.cpu_time(end+1) = node_results.cpu_time;
    merged.wall_time(end+1) = node_results.wall_time;

    ## determine index into merged results cell array, and create new entry if needed
    argument_str = stringify(node_results.arguments);
    idx = find(strcmp(argument_str, argument_strs));
    if isempty(idx)
      idx = length(argument_strs) + 1;
      argument_strs{idx, 1} = argument_str;
      merged.arguments{idx, 1} = node_results.arguments;
      merged.results{idx, 1:length(node_results.results)} = [];
      merged.jobs_per_result(idx, 1) = 0;
    endif
    ++merged.jobs_per_result(idx);

    ## convert arguments to struct, if possible
    try
      arguments = struct(node_results.arguments{:});
    catch
      arguments = node_results.arguments;
    end_try_catch

    ## merge job node results using merge function
    for i = 1:numel(node_results.results)
      merged.results{idx, i} = feval(merge_function{i}, merged.results{idx, i}, node_results.results{i}, arguments);
    endfor

    ## mark job as having been merged
    merged.jobs_to_merge(merged.jobs_to_merge == n) = [];

    ## save merged jobs results at periodic intervals
    ++job_merged_count;
    if mod(job_merged_count, job_save_period) == 0
      printf("%s: saving '%s' ...", funcName, dag_merged_file);
      save("-binary", "-zip", dag_merged_file, "merged");
      printf(" done\n");
    endif

    ## print progress
    prog = printProgress(prog, job_merged_count, job_merged_total);

  endfor

  ## if given, call normalisation function for each merged results
  if !isempty(norm_function)
    for idx = 1:size(merged.results, 1)
      for i = 1:size(merged.results, 2)
        merged.results{idx, i} = feval(norm_function{i}, merged.results{idx, i}, merged.jobs_per_result(idx));
      endfor
    endfor
  endif

  ## flatten merged arguments into struct array, if possible
  try
    arguments = struct;
    for idx = 1:length(merged.arguments)
      arguments(idx, 1) = struct(merged.arguments{idx}{:});
    endfor
    merged.arguments = arguments;
  end_try_catch

  ## flatten merged results into struct array, if possible
  try
    results = struct;
    for idx = 1:size(merged.results, 1)
      for i = 1:size(merged.results, 2)
        results(idx, i) = merged.results{idx, i};
      endfor
    endfor
    merged.results = results;
  end_try_catch

  ## save merged job results for later use
  if isempty(merged.jobs_to_merge)
    merged = rmfield(merged, "jobs_to_merge");
  endif
  printf("%s: saving '%s' ...", funcName, dag_merged_file);
  save("-binary", "-zip", dag_merged_file, "merged");
  printf(" done\n");

endfunction