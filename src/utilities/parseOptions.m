## Copyright (C) 2011 Karl Wette
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

## Kitchen-sink options parser.
## Syntax:
##   paropts = parseOptions(opts, optspec, optspec, ...)
## where:
##   opts    = function options
##   optspec = option specification, one of:
##      * required option:  {'name','types'}
##      * optional option:  {'name','types',defvalue}
##      where:
##         name     = name of option variable
##         types    = datatype specification of option:
##                    'type,type,...'
##         defvalue = default value given to <name>
##   paropts = parsed function options (optional)
## Notes:
##   * <name> will be assigned values in the context of
##     the calling function, unless paropts is given
##   * each 'type' in <types> must correspond to a function
##     'istype': each function will be called to check that
##     a value is valid. For example, if
##        <types> = 'numeric,scalar'
##     then a value <x> must satisfy:
##        isnumeric(x) && isscalar(x)
##   * <opts> should contain options of the form
##        reg,reg,...,"key",val,"key",val,...
##     where <reg> are regular options and <key>-<val> are
##     keyword-value option pairs. Regular options are
##     assigned in the order they were given as <optspec>s;
##     regular options may also be given as keyword-values.

function paropts = parseOptions(opts, varargin)

  ## check for option specifications
  if length(varargin) == 0
    error("%s: Expected option specifications in varargin", funcName);
  endif

  ## store information about options
  allowed = struct;
  required = struct;
  reqnames = {};
  typefunc = struct;
  varname = struct;

  ## parse option specifications
  for n = 1:length(varargin)
    optspec = varargin{n};

    ## basic syntax checking
    if !iscell(optspec) || !ismember(length(optspec), 2:3) || !all(cellfun("ischar", optspec(1:2)))
      error("%s: Expected option specification {'name','type'[,defvalue]} at varargin{%i}", funcName, n);
    endif

    ## store option name as an allowed option
    optname = optspec{1};
    allowed.(optname) = 1;

    ## store option type functions
    opttypes = optspec{2};
    typefuncstr = sprintf("&&is%s(x)", strtrim(strsplit(opttypes, ",", true)){:})(3:end);
    typefunc.(optname) = inline(typefuncstr, "x");
    try
      feval(typefunc.(optname), []);
    catch
      error("%s: Error parsing types specification '%s' for option", opttypes, optname);
    end_try_catch

    ## if this is an optional option
    if length(optspec) == 3

      ## assign default value, if it's the right type
      optvalue = optspec{3};
      if !(isempty(optvalue) || feval(typefunc.(optname), optvalue))
        error("%s: Default value of '%s' must be empty or satisfy: %s", funcName, optname, formula(typefunc.(optname)));
      endif
      paropts.(optname) = optvalue;

    else

      ## mark this option as being required, and store its name
      required.(optname) = 1;
      reqnames{end+1} = optname;

    endif

  endfor
      
  ## split function arguments into regular options and keyword-value pairs
  [regopts, kvopts] = parseparams(opts);
  
  ## check if there's more regular options than required options
  if length(regopts) > length(reqnames)
    error("%s: Too many regular arguments; maximum is %i", funcName, length(reqnames))
  endif
  
  ## assign regular options in order given by 'reqnames'
  for n = 1:length(regopts)
    
    ## assign option value, if it's the right type
    if !feval(typefunc.(reqnames{n}), regopts{n})
      error("%s: Value of '%s' must satisfy: %s", funcName, reqnames{n}, formula(typefunc.(reqnames{n})));
    endif
    paropts.(reqnames{n}) = regopts{n};
    
    ## mark that this option has been used
    --allowed.(reqnames{n});
    --required.(reqnames{n});
    
  endfor
  
  ## check that there's an even number of items in the keyword-value list
  if mod(length(kvopts), 2) != 0
    error("%s: Expected 'key',value pairs following regular options in args", funcName);
  endif
  
  ## assign keyword-value options
  for n = 1:2:length(kvopts)
    optkey = kvopts{n};
    optval = kvopts{n+1};

    ## check that this option is an allowed option
    if !isfield(allowed, optkey)
      error("%s: Unknown option '%s'", funcName, optkey);
    endif

    ## if option does not accept a 'char' value, but option value is a 'char',
    ## try evaluating it (this is used when parsing arguments from the command line)
    if !feval(typefunc.(optkey), "string") && ischar(optval)
      try
        eval(sprintf("optval=[%s];", optval));
      catch
        error("%s: Could not create a value from '%s'", funcName, optvalstr);
      end_try_catch
    endif

    ## assign option value, if it's the right type
    if !feval(typefunc.(optkey), optval)
      error("%s: Value of '%s' must satisfy: %s", funcName, optkey, formula(typefunc.(optkey)));
    endif
    paropts.(optkey) = optval;
    
    ## mark that this option has been used
    --allowed.(optkey);
    if isfield(required, optkey)
      --required.(optkey);
    endif
    
  endfor
  
  ## check that options have been used correctly
  allnames = fieldnames(allowed);
  for n = 1:length(allnames)

    ## if allowed < 0, option have been used more than once
    if allowed.(allnames{n}) < 0
      error("%s: Option '%s' used multiple times", funcName, allnames{n});
    endif

    if isfield(required, allnames{n})

      ## if required > 0, required option have been used at all
      if required.(allnames{n}) > 0
        error("%s: Missing required option '%s'", funcName, allnames{n});
      endif

      ## if required < 0, option have been used more than once
      if required.(allnames{n}) < 0
        error("%s: Option '%s' used multiple times", funcName, allnames{n});
      endif

    endif

  endfor

  ## assign values to option variables in caller namespace
  if nargout == 0
    paroptnames = fieldnames(paropts);
    for n = 1:length(paroptnames)
      assignin("caller", paroptnames{n}, paropts.(paroptnames{n}));
    endfor
  endif

endfunction
