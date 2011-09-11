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

## Calculate the vectors along which a pure plus/cross gravitational
## wave create no space-time peturbation
## Syntax:
##   [xp, yp, xx, yx] = PolarisationNullVectors(alpha, sdelta, psi)
## where:
##   xp,yp  = plus polarisation null vectors in equatorial coordinates
##   xx,yx  = cross polarisation null vectors in equatorial coordinates
##   alpha  = source right ascension in radians
##   sdelta = sine of source declination
##   psi    = source polarisation angle in radians

function [xp, yp, xx, yx] = PolarisationNullVectors(alpha, sdelta, psi)

  ## make inputs the same size
  [err, alpha, sdelta, psi] = common_size(alpha, sdelta, psi);
  if err > 0
    error("%s: alpha, sdelta, and psi are not of common size", funcName);
  endif

  ## make inputs row vectors
  alpha = alpha(:)';
  sdelta = sdelta(:)';
  psi = psi(:)';

  ## cosine and sine terms of cross polarisation vectors
  c1 = cos(psi);               # cos(-psi)
  s1 = -sin(psi);              # sin(-psi)
  c2 = -sdelta;                # cos(-pi/2 - delta)
  s2 = -sqrt(1 - sdelta.^2);   # sin(-pi/2 - delta)
  c3 = sin(alpha);             # cos(pi/2 - alpha)
  s3 = cos(alpha);             # sin(pi/2 - alpha)
  
  ## cross polarisation vectors
  xx = [ c1.*c3 - c2.*s1.*s3; -c1.*s3 - c2.*c3.*s1;  s1.*s2 ];
  yx = [ c3.*s1 + c1.*c2.*s3; -s1.*s3 + c1.*c2.*c3; -c1.*s2 ];

  ## plus polarisation vectors
  xp = (xx - yx) / sqrt(2);
  yp = (xx + yx) / sqrt(2);

endfunction