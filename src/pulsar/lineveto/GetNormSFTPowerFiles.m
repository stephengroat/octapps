## Copyright (C) 2013 David Keitel
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


function ret = GetNormSFTPowerFiles ( varargin )
 ## ret = GetNormSFTPowerFiles ( varargin )
 ## function to produce files of normalized SFT power over a large set of frequency bands (input sft files) for a single IFO
 ## command-line parameters can be taken from parseOptions call below
 ## example call: octapps_run GetNormSFTPowerFiles --sftdir=sfts --sft_filenamebit=S6GC1 --IFO=h1 --freqmin=50.5

 # read in and check input parameters
 params_init = parseOptions(varargin,
                     {"sftdir", "char"},
                     {"sft_filenamebit", "char", ""},
                     {"sft_width", "numeric,scalar", 0.05},
                     {"Tsft", "numeric,scalar", 1800},
                     {"IFO", "char"},
                     {"timestampsfile", "char", ""},
                     {"freqmin", "numeric,scalar"},
                     {"freqmax", "numeric,scalar", 0}, # default: set to freqmin+freqstep
                     {"freqstep", "numeric,scalar", 0.05},
                     {"workingdir", "char", "."},
                     {"lalpath", "char", ""},
                     {"outfile", "char", "normSFTpower.dat"},
                     {"rngmedbins", "numeric,scalar", 101},
                     {"output_column_headings", "numeric,scalar", 1},
                     {"output_align", "numeric,scalar", 1},
                     {"output_freq", "numeric,scalar", 1},
                     {"output_normSFT", "numeric,scalar", 1},
                     {"output_01", "numeric,scalar", 0},
                     {"SFTpower_thresh", "numeric,scalar", 0},
                     {"SFTpower_fA", "numeric,scalar", 0},
                     {"debug", "numeric,scalar", 0},
                     {"cleanup", "numeric,scalar", 1}
                );
 writeCommandLineToFile ( params_init.outfile, params_init, mfilename );
 params_init = check_input_parameters ( params_init ); # this already processes some of the input params, so have to do output before

 format long;
 global SMALL_EPS = 1.0e-6;

 if ( params_init.debug == 1 )
  printf("Running from directory '%s'. LAL path is '%s'. Local octave version is '%s'. Input parameters are:\n", pwd, params_init.lalpath, version);
  params_init
 endif

 lalapps_version_string = getLalAppsVersionInfo ([params_init.lalpath, "lalapps_ComputePSD"]);
 fid = fopen ( params_init.outfile, "a" ); # append mode
 fprintf ( fid, lalapps_version_string );
 fclose ( params_init.outfile );

 # prepare PSD code and parameters
 if ( params_init.debug == 0 )
  ComputePSD      = [params_init.lalpath, "lalapps_ComputePSD -v0"];
 else
  ComputePSD      = [params_init.lalpath, "lalapps_ComputePSD -v1"];
 endif
 params_psd.outputNormSFT = 1;
 params_psd.PSDmthopSFTs  = 1;
 params_psd.FreqBand      = params_init.freqstep;
 params_psd.blocksRngMed  = params_init.rngmedbins;
 if ( length(params_init.timestampsfile) > 0 )
  params_psd.timeStampsFile = params_init.timestampsfile;
 endif
 thresh = params_init.SFTpower_thresh;

 # count necessary freqbands and sfts
 # NOTE: rounded down, freqmax may not be reached if freqmax-freqmin is not an integer multiple of freqstep
 num_freqsteps = floor ( ( params_init.freqmax - params_init.freqmin ) / params_init.freqstep + SMALL_EPS );

 # prepare output structs and counting variables
 normSFTpower     = [];
 thresh_crossings = [];
 frequencies      = [];
 curr_step        = 0;

 # prepare temporary directory, if it does not exist yet
 if ( isdir ( params_init.workingdir ) )
   temp_working_dir = 0;
 else
  printf("Working directory '%s' does not exist yet, creating it...\n", params_init.workingdir );
  [status, msg, msgid] = mkdir ( params_init.workingdir );
  if ( status != 1 )
   error (["Failed to create output directory '", params_init.workingdir , "': msg = ", msg, "\n"] );
  endif
  temp_working_dir = 1;
 endif

 # main loop over freqbands - break when params_run.FreqMax reached
 while ( curr_step < num_freqsteps )

  curr_step++;
  curr_freq = params_init.freqmin + (curr_step-1)*params_init.freqstep;

  printf("Frequency band %d/%d: processing [%f,%f] Hz...\n", curr_step, num_freqsteps, curr_freq, curr_freq+params_init.freqstep );

  # get the correct sft range, adding running median sideband
  [sftstartfreq, num_sfts_to_load] = get_sft_range ( params_init, curr_freq );

  # find all required sfts
  [sfts, firstsft] = get_EatH_sft_paths ( params_init, sftstartfreq, num_sfts_to_load, params_init.IFO );

  if ( ( curr_step == 1 ) && ( params_init.SFTpower_fA > 0 ) )
   printf("First band, converting SFTpower_fA=%g to SFTpower_thresh", params_init.SFTpower_fA);
   if ( length(params_init.timestampsfile) > 0 ) # get number of SFTs from timestamps
    printf(" using num_SFTs from timestamps files...\n");
    timestamps = load(params_init.timestampsfile);
    num_SFTs = length(timestamps);
   else # get number of SFT bins needed to convert from fA to thresh
    printf(" using num_SFTs from input SFTs...\n");
    printf("Getting num_SFTs from input file '%s' ...\n", firstsft);
    num_SFTs = get_num_SFTs_from_file ( firstsft );
   endif
   thresh = compute_SFT_power_threshold_from_fA ( params_init.SFTpower_fA, num_SFTs );
   printf("num_SFTs=%d, threshold=%f\n", num_SFTs, thresh);
  endif

  # get normalized SFT power
  params_psd.Freq           = curr_freq;
  params_psd.inputData      = sfts;
  params_psd.outputPSD      = [params_init.workingdir, filesep, "psd_med_", num2str(params_psd.blocksRngMed), "_band_", int2str(curr_step), ".dat"];
  runCode ( params_psd, ComputePSD );
  psd = load(params_psd.outputPSD);
  normSFTpower = cat(1,normSFTpower,psd(:,3));
  if ( params_init.output_freq == 1 )
   frequencies = cat(1,frequencies,psd(:,1));
  endif
  if ( params_init.output_01 == 1 )
   thresh_crossings = cat(1,thresh_crossings,ge(psd(:,3),thresh));
  endif
  if ( params_init.cleanup == 1 )
   [err, msg] = unlink (params_psd.outputPSD);
  endif

 endwhile # main loop over freqbands

 # save resuls to file as an ascii matrix with custom header
 write_results_to_file (params_init, frequencies, normSFTpower, thresh_crossings );

 # if we created a temporary working directory, remove it again
 if ( ( params_init.cleanup == 1 ) && ( temp_working_dir == 1 ) )
  [status, msg, msgid] = rmdir ( params_init.workingdir );
  if ( status != 1 )
   error (["Failed to remove temporary working directory '", params_init.workingdir, "': msg = ", msg, ", msgid = ", msgid, "\n"]);
  endif
 endif

 ret = 1;

endfunction # GetNormSFTPowerFiles()

############## AUXILIARY FUNCTIONS #############

function [params_init] = check_input_parameters ( params_init )
 ## [params_init] = check_input_parameters ( params_init )
 ## function to parse argument list into variables and check consistency

 if ( !isdir(params_init.sftdir) )
  error(["Invalid input parameter (sftdir): ", params_init.sftdir, " is not a directory."])
 endif

 if ( params_init.freqmin < 0.0 )
  error(["Invalid input parameter (freqmin): ", num2str(params_init.freqmin), " must be >= 0."]);
 endif

 if ( params_init.freqmax == 0 )
  params_init.freqmax = params_init.freqmin+params_init.freqstep;
 elseif ( params_init.freqmax < params_init.freqmin )
  error(["Invalid input parameter (freqmax): ", num2str(params_init.freqmax), " is lower than freqmin=", num2str(params_init.freqmin), "."]);
 endif

 if ( params_init.freqstep <= 0.0 )
  error(["Invalid input parameter (freqstep): ", num2str(params_init.freqstep), " must be > 0."]);
 endif

 if ( ( length(params_init.lalpath) > 0 ) && ( !isdir(params_init.lalpath) ) )
  error(["Invalid input parameter (lalpath): ", params_init.lalpath, " is not a directory."]);
 endif

 if ( params_init.rngmedbins < 0 )
   error(["Invalid input parameter (rngmedbins): ", num2str(params_init.rngmedbins), " must be >= 0."])
 endif

 if ( params_init.sft_width <= 0.0 )
  error(["Invalid input parameter (sft_width): ", num2str(params_init.sft_width), " must be > 0."]);
 endif

 if ( params_init.Tsft <= 0.0 )
  error(["Invalid input parameter (Tsft): ", num2str(params_init.Tsft), " must be > 0."]);
 else
  params_init.sft_dfreq = 1.0/params_init.Tsft;
 endif

 if ( ( length(params_init.timestampsfile) > 0 ) && ( exist(params_init.timestampsfile,"file") != 2 ) )
  error(["Invalid input parameter (timestampsfile): ", params_init.timestampsfile, " is neither 'none' nor an existing file."]);
 endif

 if ( ( params_init.output_column_headings != 0 ) && ( params_init.output_column_headings != 1 ) )
  error(["Invalid input parameter (output_column_headings): ", int2str(params_init.output_column_headings), " is neither 0 or 1."])
 endif

 if ( ( params_init.output_align != 0 ) && ( params_init.output_align != 1 ) )
  error(["Invalid input parameter (output_align): ", int2str(params_init.output_align), " is neither 0 or 1."])
 endif

 if ( ( params_init.output_freq != 0 ) && ( params_init.output_freq != 1 ) )
  error(["Invalid input parameter (output_freq): ", int2str(params_init.output_freq), " is neither 0 or 1."])
 endif

 if ( ( params_init.output_normSFT != 0 ) && ( params_init.output_normSFT != 1 ) )
  error(["Invalid input parameter (output_normSFT): ", int2str(params_init.output_normSFT), " is neither 0 or 1."])
 endif

 if ( ( params_init.output_01 != 0 ) && ( params_init.output_01 != 1 ) )
  error(["Invalid input parameter (output_01): ", int2str(params_init.cleanup), " is neither 0 or 1."])
 endif

 if ( params_init.SFTpower_thresh < 0 )
   error(["Invalid input parameter (SFTpower_thresh): ", num2str(params_init.SFTpower_thresh), " must be positive (or 0 to not use)."])
 endif

 if ( params_init.SFTpower_fA < 0 )
  error(["Invalid input parameter (SFTpower_fA): '", num2str(params_init.SFTpower_fA), "' must be positive (or 0 to not use)."])
 endif

 if ( ( params_init.debug != 0 ) && ( params_init.debug != 1 ) )
  error(["Invalid input parameter (debug): ", int2str(params_init.debug), " is neither 0 or 1."])
 endif

 if ( ( params_init.cleanup != 0 ) && ( params_init.cleanup != 1 ) )
  error(["Invalid input parameter (cleanup): ", int2str(params_init.cleanup), " is neither 0 or 1."])
 endif

endfunction # check_input_parameters()


function [sftstartfreq, num_sfts_to_load] = get_sft_range ( params_init, startfreq )
 ## [sftstartfreq, num_sfts_to_load] = get_sft_range ( params_init, startfreq )
 ## function to compute the necessary SFT start frequency and the number of (contiguous) SFTs starting from there

 sftstartfreq = floor(20*startfreq)/20; # round down to get SFT file containing the startfreq
 num_sfts_to_load = ceil ( params_init.freqstep / params_init.sft_width );
 rngmed_wing = fix(params_init.rngmedbins/2 + 1) * params_init.sft_dfreq;

 # load more SFTs if below the lower boundary
 while ( startfreq - rngmed_wing < sftstartfreq + params_init.sft_dfreq )
  sftstartfreq -= params_init.sft_width;
  num_sfts_to_load++;
 endwhile

 # load more SFTs if above the upper boundary
 while ( startfreq + params_init.freqstep + rngmed_wing >= sftstartfreq + num_sfts_to_load*params_init.sft_width - params_init.sft_dfreq )
  num_sfts_to_load++;
 endwhile

endfunction # get_sft_range()


function write_results_to_file ( params_init, frequencies, normSFTpower, thresh_crossings )
 ## write_results_to_file ( params_init, frequencies, normSFTpower, thresh_crossings )
 ## save outliers to file as an ascii matrix with custom header

 fid = fopen ( params_init.outfile, "a" ); # append mode (commandline has already been written into this file)

 formatstring_body = "";
 m = 0;
 if ( params_init.output_freq == 1 )
  m++;
  columnlabels{m} = "freq";
  if ( params_init.output_align == 1 )
   formatstring_body = [formatstring_body, "%%%d.6f "];
   majordigits(m)  = 4;
   minordigits(m)  = 6;
   columnwidths(m) = majordigits(m)+1+minordigits(m);
  else
   formatstring_body = [formatstring_body, "%.6f "];
  endif
 endif
 if ( params_init.output_normSFT == 1 )
  m++;
  columnlabels{m} = "normSFTpower";
  if ( params_init.output_align == 1 )
   formatstring_body = [formatstring_body, "%%%d.6f "];
   majordigits(m)  = 4;
   minordigits(m)  = 6;
   columnwidths(m) = majordigits(m)+1+minordigits(m);
  else
   formatstring_body = [formatstring_body, "%.6f "];
  endif
 endif
 if ( params_init.output_01 == 1 )
  m++;
  columnlabels{m} = ">thresh?";
  if ( params_init.output_align == 1 )
   formatstring_body = [formatstring_body, "%%%dd"];
   majordigits(m)  = 1;
   minordigits(m)  = 0;
   columnwidths(m) = majordigits(m)+0+minordigits(m);
  else
   formatstring_body = [formatstring_body, "%d "];
  endif
 endif
 formatstring_body = [formatstring_body, "\n"];

 if ( params_init.output_freq == 0 )
  fprintf ( fid, "# startfreq is in first line\n" );
  fprintf ( fid, "%.6f\n", params_init.freqmin );
 endif

 if ( params_init.output_column_headings == 1 )
  fprintf ( fid, "# columns:\n" );
  formatstring_header = "#";
  if ( params_init.output_align == 1 ) # pad headings if numbers will be wider
   for n = 1:1:length(columnlabels)
    formatstring_header = [formatstring_header, " %%%ds"];
    columnwidths(n) = max(length(columnlabels{n}),columnwidths(n));
   endfor
   formatstring_header = sprintf(formatstring_header, columnwidths);
  else
   for n = 1:1:length(columnlabels)
    formatstring_header = [formatstring_header, " %s"];
   endfor
  endif
  formatstring_header = [formatstring_header, "\n"];
  fprintf ( fid, formatstring_header, columnlabels{:} );
 endif

 # body
 if ( params_init.output_align == 1 )
  if ( params_init.output_column_headings == 1 )
   columnwidths(1) += 2; # now need to pad for leading "# " in heading also
  endif
  formatstring_body = sprintf(formatstring_body, columnwidths); # pad to standard width
 endif
 for n=1:1:length(normSFTpower)
  m = 0;
  if ( params_init.output_freq == 1 )
   m++;
   outvalues{m} = frequencies(n);
  endif
  if ( params_init.output_normSFT == 1 )
   m++;
   outvalues{m} = normSFTpower(n);
  endif
  if ( params_init.output_01 == 1 )
   m++;
   outvalues{m} = thresh_crossings(n);
  endif
  fprintf ( fid, formatstring_body, outvalues{:} );
 endfor

 # done
 fclose ( params_init.outfile );

endfunction # write_results_to_file()