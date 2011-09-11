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

## Calculate sensitivity in terms of the root-mean-square SNR
## Syntax:
##   [rho, pd_rho] = SensitivitySNR(paNt, pd, Ns, Rsqr_H, detstat, ...)
## where:
##   rho     = detectable r.m.s. SNR (per segment)
##   pd_rho  = calculated false dismissal probability
##   paNt    = false alarm probability (per template)
##   pd      = false dismissal probability
##   Ns      = number of segments
##   Rsqr_H  = histogram of SNR "geometric factor" R^2
##   detstat = detection statistic, one of:
##      "ChiSqr": chi^2 statistic, e.g. the F-statistic
##                see SensitivityChiSqrFDP for possible options

function [rho, pd_rho] = SensitivitySNR(paNt, pd, Ns, Rsqr_H, detstat, varargin)

  ## display progress updates?
  global sensitivity_progress;
  if isempty(sensitivity_progress)
    sensitivity_progress = false;
  endif
  if sensitivity_progress
    old_pso = page_screen_output(0);
    fprintf("%s: starting\n", funcName);
  endif

  ## check input
  assert(all(paNt > 0));
  assert(all(pd > 0));
  assert(all(Ns > 0));
  assert(isHist(Rsqr_H) || isempty(Rsqr_H));

  ## make sure paNt, pd, and Ns are the same size
  [cserr, paNt, pd, Ns] = common_size(paNt, pd, Ns);
  if cserr > 0
    error("%s: paNt, pd, and Ns are not of common size", funcName);
  endif
  
  ## make inputs column vectors
  siz = size(paNt);
  paNt = paNt(:);
  pd = pd(:);
  Ns = Ns(:);

  ## select a detection statistic
  fdp_vars = {};
  switch detstat
    case "ChiSqr"   ## chi^2 statistic
      [FDP, fdp_vars, fdp_opts] = SensitivityChiSqrFDP(paNt, pd, Ns, varargin);
    otherwise
      error("%s: invalid detection statistic '%s'", funcName, detstat);
  endswitch

  ## get values and weights of R^2 as row vectors
  if isempty(Rsqr_H)
    ## singular case: R^2 = 1
    Rsqr_x = 1.0;
    Rsqr_w = 1.0;
  else
    ## from histogram
    [Rsqr_xb, Rsqr_px] = finiteHist(Rsqr_H);
    [Rsqr_x, Rsqr_dx] = histBinGrids(Rsqr_H, 1, "xc", "dx");
    Rsqr_w = Rsqr_px .* Rsqr_dx;
  endif
  Rsqr_x = Rsqr_x(:)';
  Rsqr_w = Rsqr_w(:)';
  
  ## make row indexes logical, to select rows
  ii = true(length(paNt), 1);

  ## make column indexes ones, to duplicate columns
  jj = ones(length(Rsqr_x), 1);

  ## rho is computed for each paNt, pd, Ns (dim. 1) by summing
  ## false dismissal probability for fixed Rsqr_x, weighted
  ## by Rsqr_w (dim. 2)
  Rsqr_x = Rsqr_x(ones(size(ii)), :);
  Rsqr_w = Rsqr_w(ones(size(ii)), :);

  ## initialise variables
  pd_rho = rhosqr = nan(size(paNt, 1), 1);
  pd_rho_min = pd_rho_max = zeros(size(rhosqr));

  ## calculate the false dismissal probability for rhosqr=0,
  ## only proceed if it's less than the target false dismissal
  ## probability
  rhosqr_min = zeros(size(rhosqr));
  pd_rho_min(ii) = callFDP(rhosqr_min,ii,
                           jj,paNt,pd,Ns,Rsqr_x,Rsqr_w,
                           FDP,fdp_vars,fdp_opts);
  ii0 = (pd_rho_min >= pd);

  ## find rhosqr_max where the false dismissal probability becomes
  ## less than the target false dismissal probability, to bracket
  ## the range of rhosqr
  rhosqr_max = ones(size(rhosqr));
  ii = ii0;
  sumii = 0;
  do

    ## display progress updates?
    if sensitivity_progress && sum(ii) != sumii
      sumii = sum(ii);
      fprintf("%s: finding rhosqr_max (%i left)\n", funcName, sumii);
    endif

    ## increment upper bound on rhosqr
    rhosqr_max(ii) *= 2;

    ## calculate false dismissal probability
    pd_rho_max(ii) = callFDP(rhosqr_max,ii,
                             jj,paNt,pd,Ns,Rsqr_x,Rsqr_w,
                             FDP,fdp_vars,fdp_opts);
    
    ## determine which rhosqr to keep calculating for
    ## exit when there are none left
    ii = (pd_rho_max >= pd);
  until !any(ii)
  
  ## find rhosqr using a bifurcation search
  err1 = inf(size(rhosqr));
  err2 = inf(size(rhosqr));
  ii = ii0;
  sumii = 0;
  do

    ## display progress updates?
    if sensitivity_progress && sum(ii) != sumii
      sumii = sum(ii);
      fprintf("%s: bifurcation search (%i left)\n", funcName, sumii);
    endif

    ## pick random point within range as new rhosqr
    u = rand(size(rhosqr));
    rhosqr(ii) = rhosqr_min(ii) .* u(ii) + rhosqr_max(ii) .* (1-u(ii));
      
    ## calculate new false dismissal probability
    pd_rho(ii) = callFDP(rhosqr,ii,
                         jj,paNt,pd,Ns,Rsqr_x,Rsqr_w,
                         FDP,fdp_vars,fdp_opts);
    
    ## replace bounds with mid-point as required
    iimin = ii & (pd_rho_min > pd & pd_rho > pd);
    iimax = ii & (pd_rho_max < pd & pd_rho < pd);
    rhosqr_min(iimin) = rhosqr(iimin);
    pd_rho_min(iimin) = pd_rho(iimin);
    rhosqr_max(iimax) = rhosqr(iimax);
    pd_rho_max(iimax) = pd_rho(iimax);
     
    ## fractional error in false dismissal rate
    err1(ii) = abs(pd_rho(ii) - pd(ii)) ./ pd(ii);

    ## fractional range of rhosqr
    err2(ii) = (rhosqr_max(ii) - rhosqr_min(ii)) ./ rhosqr(ii);

    ## determine which rhosqr to keep calculating for
    ## exit when there are none left
    ii = (isfinite(err1) & err1 > 1e-3) & (isfinite(err2) & err2 > 1e-8);
  until !any(ii)

  ## return detectable SNR
  rho = sqrt(rhosqr);
  rho = reshape(rho, siz);
  pd_rho = reshape(pd_rho, siz);
  
  ## display progress updates?
  if sensitivity_progress
    fprintf("%s: done\n", funcName);
    page_screen_output(old_pso);
  endif

endfunction

## call a false dismissal probability calculation equation
function pd_rho = callFDP(rhosqr,ii,
                          jj,paNt,pd,Ns,Rsqr_x,Rsqr_w,
                          FDP,fdp_vars,fdp_opts)
  if any(ii)
    pd_rho = sum(feval(FDP,
                       paNt(ii,jj), pd(ii,jj), Ns(ii,jj),
                       rhosqr(ii,jj).*Rsqr_x(ii,:),
                       cellfun(@(x) x(ii,jj), fdp_vars,
                               "UniformOutput", false),
                       fdp_opts
                       ) .* Rsqr_w(ii,:), 2);
  else
    pd_rho = [];
  endif
endfunction