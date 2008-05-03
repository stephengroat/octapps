%% Return the "lattice-volume", i.e. the volume of an elementary lattice-cell
%% for an An* lattice in n dimensions.
%% This is referring to the lattice-definition corresponding to the generator
%% returned by AnsLatticeGenerator.m, i.e. Eq.(76) of Conway&Sloane99:
%% [this function can handle vector input]

%%
%% Copyright (C) 2008 Reinhard Prix
%%
%%  This program is free software; you can redistribute it and/or modify
%%  it under the terms of the GNU General Public License as published by
%%  the Free Software Foundation; either version 2 of the License, or
%%  (at your option) any later version.
%%
%%  This program is distributed in the hope that it will be useful,
%%  but WITHOUT ANY WARRANTY; without even the implied warranty of
%%  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%%  GNU General Public License for more details.
%%
%%  You should have received a copy of the GNU General Public License
%%  along with with program; see the file COPYING. If not, write to the
%%  Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
%%  MA  02111-1307  USA
%%

function vol = AnsVolume ( dim )

  vol = 1 ./ sqrt ( dim + 1 );

  return;

endfunction %% AnsVolume()
