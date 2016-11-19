#!/usr/bin/env perl

# This script does sensitivity analysis
# on a strategy.

use strict;
use warnings;

my $strategy = 'sell_and_hold';

# Strategy options -- see $strategy.pl for details.
my $beg_YEARS = 10;
my $end_YEARS = 50;
my $inc_YEARS = 10;
my $beg_VALLEY_THRESHOLD = 1.05;
my $end_VALLEY_THRESHOLD = 1.05;
my $inc_VALLEY_THRESHOLD = .05;
my $beg_SELL_THRESHOLD = 0.90;
my $end_SELL_THRESHOLD = 0.90;
my $inc_SELL_THRESHOLD = 0.05;

for (my $tmp_YEARS = $beg_YEARS; $tmp_YEARS <= $end_YEARS; $tmp_YEARS+=$inc_YEARS) {
    for (my $tmp_VALLEY_THRESHOLD = $beg_VALLEY_THRESHOLD; $tmp_VALLEY_THRESHOLD <= $end_VALLEY_THRESHOLD; $tmp_VALLEY_THRESHOLD+=$inc_VALLEY_THRESHOLD) {
        for (my $tmp_SELL_THRESHOLD = $beg_SELL_THRESHOLD; $tmp_SELL_THRESHOLD <= $end_SELL_THRESHOLD; $tmp_SELL_THRESHOLD+=$inc_SELL_THRESHOLD) {
            my $results = `perl $strategy.pl --years=$tmp_YEARS --valley_threshold=$tmp_VALLEY_THRESHOLD --sell_threshold=$tmp_SELL_THRESHOLD`;

            print qq(\n\nYEARS: $tmp_YEARS; VALLEY_THRESHOLD: $tmp_VALLEY_THRESHOLD; SELL_THRESHOLD: $tmp_SELL_THRESHOLD\n$results\n);
        }
    }
}
