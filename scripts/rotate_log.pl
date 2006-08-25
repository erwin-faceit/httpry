#!/usr/bin/perl -w

#
# rotate_log.pl | created: 6/27/2005
#
# Copyright (c) 2006, Jason Bittel <jbittel@corban.edu>. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# 3. Neither the name of the author nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
# IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

use strict;
use Getopt::Std;
use Time::Local;

# -----------------------------------------------------------------------------
# GLOBAL CONSTANTS
# -----------------------------------------------------------------------------
my $TAR  = "tar";
my $GZIP = "gzip";

# -----------------------------------------------------------------------------
# GLOBAL VARIABLES
# -----------------------------------------------------------------------------
my %opts;
my $compress = 0;
my $del_text = 0;
my $input_file;
my $purge_limit;
my $purge_size;
my $output_dir;
my @dir_list;

# -----------------------------------------------------------------------------
# Main Program
# -----------------------------------------------------------------------------
&get_arguments();

# Read contents of directory into array
$output_dir =~ s/\/$//; # Remove trailing slash
opendir(DIR, $output_dir) or die "Error: Cannot open directory $output_dir\n";
        @dir_list = map "$output_dir/$_", grep !/^\./, readdir(DIR);
closedir(DIR);

# Process log file/directory commands
&compress_files() if $compress;
if ($del_text) {
        foreach (grep /\.txt$/, @dir_list) {
                unlink;
        }
}
&move_file() if $input_file;
&purge_dir_by_count() if $purge_limit;
&purge_dir_by_size() if $purge_size;

# -----------------------------------------------------------------------------
# Iterate through log files, compressing them in tar.gz format
# -----------------------------------------------------------------------------
sub compress_files {
        my $log_file;
        my $filename;
        my $dir;

        $dir = `pwd`;
        chdir($output_dir); # Must be in local dir for relative paths in tar file

        foreach $log_file (grep /\.log$/, @dir_list) {
                # Compress log file
                $log_file =~ /.*\/(.+?)\.log$/;
                $filename = $1;

                if ((system "$TAR cf - $filename.log | $GZIP -9 > $output_dir/$filename.tar.gz") == 0) {
                        unlink $log_file;
                } else {
                        print "Error: Cannot compress log file '$log_file'\n";
                }
        }

        chdir($dir);

        return;
}

# -----------------------------------------------------------------------------
# Move current log file to archive directory and rename according to date
# -----------------------------------------------------------------------------
sub move_file {
        my $mday;
        my $mon;
        my $year;

        if (-e $input_file) {
                # Create destination filename
                $mday = (localtime)[3];
                $mon  = (localtime)[4] + 1;
                $year = (localtime)[5] + 1900;

                # Create destination folder
                if (! -e $output_dir) {
                        mkdir $output_dir;
                }

                rename "$input_file", "$output_dir/$mon-$mday-$year.log";
        } else {
                print "Error: Input file '$input_file' does not exist\n";
        }

        return;
}

# -----------------------------------------------------------------------------
# Remove oldest files if total file count is above specified purge limit
# -----------------------------------------------------------------------------
sub purge_dir_by_count {
        my @logs;
        my $del_count;

        # Sort all compressed archives in the directory according
        # to the date in the filename
        @logs = map $_->[0],
                sort {
                        $a->[3] <=> $b->[3] or # Sort by year...
                        $a->[1] <=> $b->[1] or # ...then by month...
                        $a->[2] <=> $b->[2]    # ...and finally day
                }
                map [ $_, /(\d+)-(\d+)-(\d+)/ ], grep /(\.tar\.gz$|\.log$)/, @dir_list;

        if (scalar @logs > $purge_limit) {
                $del_count = scalar @logs - $purge_limit;
                for (my $i = 0; $i < $del_count; $i++) {
                        unlink $logs[$i];
                }
        }

        return;
}

# -----------------------------------------------------------------------------
# Remove oldest files if total file size is above specified size limit
# -----------------------------------------------------------------------------
sub purge_dir_by_size {
        my @logs;
        my $log_file;
        my $file_size;

        # Sort all compressed archives in the directory according
        # to the date in the filename
        @logs = map $_->[0],
                sort {
                        $a->[3] <=> $b->[3] or # Sort by year...
                        $a->[1] <=> $b->[1] or # ...then by month...
                        $a->[2] <=> $b->[2]    # ...and finally day
                }
                map [ $_, /(\d+)-(\d+)-(\d+)/ ], grep /(\.tar\.gz$|\.log$)/, @dir_list;

        foreach $log_file (reverse @logs) {
                $file_size += int((stat($log_file))[7] / 1000000);

                if ($file_size > $purge_size) {
                        unlink $log_file;
                }
        }

        return;
}

# -----------------------------------------------------------------------------
# Retrieve and process command line arguments
# -----------------------------------------------------------------------------
sub get_arguments {
        getopts('cd:hi:m:p:t', \%opts) or &print_usage();

        # Print help/usage information to the screen if necessary
        &print_usage() if ($opts{h});

        # Copy command line arguments to internal variables
        $compress    = 1 if ($opts{c});
        $del_text    = 1 if ($opts{t});
        $input_file  = 0 unless ($input_file  = $opts{i});
        $purge_limit = 0 unless ($purge_limit = $opts{p});
        $purge_size  = 0 unless ($purge_size  = $opts{m});
        $output_dir  = 0 unless ($output_dir  = $opts{d});

        if (!$output_dir) {
                print "Error: No output directory provided\n";
                &print_usage();
        }

        return;
}

# -----------------------------------------------------------------------------
# Print usage/help information to the screen and exit
# -----------------------------------------------------------------------------
sub print_usage {
        die <<USAGE;
Usage: $0 [-ct] [-d dir] [-i file] [-m size(MB)] [-p count]
  -c ... compress old log files
  -d ... set directory to move log to
  -i ... input log file to process
  -m ... purge old log files that exceed this size threshold
  -p ... purge old log files that exceed this count threshold
  -t ... delete all text files in target directory
USAGE
}
