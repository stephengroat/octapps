## Copyright (C) 2017 Karl Wette
##
## This program is free software; you can redistribute it and/or modify it
## under the terms of the GNU General Public License as published by
## the Free Software Foundation; either version 3 of the License, or
## (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program.  If not, see <http://www.gnu.org/licenses/>.

## Estimate the sensitivity depth of 'lalapps_Weave'.
## Usage:
##   depth = WeaveSensitivity("opt", val, ...)
## where:
##   depth:
##     estimated sensitivity depth
## Options:
##   setup_file:
##     Weave setup file, from which to extract segment list
##   segments,detectors,coh_Tspan,semi_Tspan:
##     Alternatives to 'setup_file'; give number of segments,
##     comma-separated list of detectors, time span of coherent
##     segments, and total time span of semicoherent search
##   alpha,delta:
##     If not searching over sky parameters, give sky point of
##     search (default: all-sky)
##   spindowns:
##     Number of spindown parameters being searched
##   lattice:
##     Type of lattice used by search (default: Ans)
##   coh_max_mismatch,semi_max_mismatch:
##     Maximum coherent and semicoherent mismatches; for a single-
##     segment or non-interpolating search, set coh_max_mismatch=0
##   Tdata:
##     total amount of data used by search, in seconds
##   pFD:
##     false dismissal probability of search
##   pFA,semi_ntmpl:
##     false alarm probability of search, and number of semicoherent
##     templates used by search
##   mean2F_th:
##     Alternatives to 'pFA','semi_ntmpl': threshold on mean 2F

function depth = WeaveSensitivity(varargin)

  ## parse options
  parseOptions(varargin,
               {"setup_file", "char", []},
               {"segments", "integer,strictpos,scalar", []},
               {"detectors", "char", []},
               {"coh_Tspan", "real,strictpos,scalar", []},
               {"semi_Tspan", "real,strictpos,scalar", []},
               {"alpha", "real,vector", []},
               {"delta", "real,vector", []},
               {"spindowns", "integer,positive,scalar"},
               {"lattice", "char", "Ans"},
               {"coh_max_mismatch", "real,positive,scalar"},
               {"semi_max_mismatch", "real,positive,scalar"},
               {"Tdata", "real,strictpos,scalar"},
               {"pFD", "real,strictpos,column", 0.1},
               {"pFA", "real,strictpos,column", []},
               {"semi_ntmpl", "real,strictpos,column", []},
               {"mean2F_th", "real,strictpos,column", []},
               []);
  assert(xor(!isempty(setup_file), !isempty(segments)), "'setup_file' and 'segments' are mutually exclusive");
  assert(xor(!isempty(setup_file), !isempty(detectors)), "'setup_file' and 'detectors' are mutually exclusive");
  assert(xor(!isempty(setup_file), !isempty(coh_Tspan)), "'setup_file' and 'coh_Tspan' are mutually exclusive");
  assert(xor(!isempty(setup_file), !isempty(semi_Tspan)), "'setup_file' and 'semi_Tspan' are mutually exclusive");
  assert(!or(!isempty(coh_Tspan), !isempty(semi_Tspan)), "'coh_Tspan' and 'semi_Tspan' are mutually required");
  assert(!or(!isempty(alpha), !isempty(delta)), "'alpha' and 'delta' are mutually required");
  assert(xor(!isempty(pFA), !isempty(mean2F_th)), "'pFA' and 'mean2F_th' are mutually exclusive");
  assert(xor(!isempty(semi_ntmpl), !isempty(mean2F_th)), "'semi_ntmpl' and 'mean2F_th' are mutually exclusive");
  assert(!or(!isempty(pFA), !isempty(semi_ntmpl)), "'pFA' and 'semi_ntmpl' are mutually required");

  ## if given, load setup file and extract number of segments and detectors
  if !isempty(setup_file)
    setup = fitsread(setup_file);
    assert(isfield(setup, "segments"));
    segments = length(setup.segments.data);
    detectors = strjoin(setup.primary.header.detect, ",");
  endif

  ## get mismatch histogram
  if !isempty(setup_file)
    args = {"setup_file", setup_file};
  else
    args = {"coh_Tspan", coh_Tspan, "semi_Tspan", semi_Tspan};
  endif
  args = {args{:}, "sky", isempty(alpha), "spindowns", spindowns, "lattice", lattice};
  args = {args{:}, "coh_max_mismatch", coh_max_mismatch, "semi_max_mismatch", semi_max_mismatch};
  mismatch_hgrm = WeaveFstatMismatch(args{:});

  ## calculate sensitivity
  args = {"Nseg", segments, "Tdata", Tdata, "misHist", mismatch_hgrm, "detectors", detectors};
  if !isempty(pFA)
    args = {args{:}, "pFD", pFD, "pFA", pFA ./ semi_ntmpl};
  else
    args = {args{:}, "pFD", pFD, "avg2Fth", mean2F_th};
  endif
  if !isempty(alpha)
    args = {args{:}, "alpha", alpha, "delta", delta};
  endif
  depth = SensitivityDepthStackSlide(args{:});

endfunction
