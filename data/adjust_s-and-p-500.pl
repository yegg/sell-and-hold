#!/usr/bin/env perl

# Turns trailing annual dividends into real dividends.

use warnings;
use strict;
use Data::Dumper;

my @dividends = ();
my @dividends2 = ();

open (IN,"<s-and-p-500.csv");
open (OUT,">s-and-p-500.adj.csv");
my $tmp = <IN>;
print OUT $tmp;
my $dividend_sum_last = 0;
my $dividend2_sum_last = 0;
LINE: while (my $line = <IN>) {
    chomp($line);
    my @line = split(/,/,$line);
    my $date = $line [0] || '';
    my $dividend_sum = $line [2] || '';
    my $dividend_real = 0;
    my $dividend2_sum = $line [7] || '';
    my $dividend2_real = 0;
    
    if (scalar(@dividends)>12) {

        print qq(\n$date\n);
        print qq(dividends: ), scalar(@dividends), qq(\n);
        print qq(dividends2: ), scalar(@dividends2), qq(\n);

        my $s1 = $dividend_sum;
        my $s2 = $dividend_sum_last;
        $dividend_real = ($s1-$s2)+$dividends[-12];
        print qq(s1: $s1\n);
        print qq(s2: $s2\n);
        print qq(dividends -12: ), $dividends[-12], qq(\n);
        print qq(dividend_real: $dividend_real\n);
        
        $s1 = $dividend2_sum;
        $s2 = $dividend2_sum_last;
        $dividend2_real = ($s1-$s2)+$dividends2[-12];
        print qq(s1: $s1\n);
        print qq(s2: $s2\n);
        print qq(dividends2 -12: ), $dividends2[-12], qq(\n);
        print qq(dividend2_real: $dividend2_real\n);

    } else {
        $dividend_real = $dividend_sum/12;
        $dividend2_real = $dividend2_sum/12;
    }

    $dividend_sum_last = $dividend_sum;
    $dividend2_sum_last = $dividend2_sum;

    push(@dividends,$dividend_real);
    push(@dividends2,$dividend2_real);
    #    print Dumper(\@dividends);
    #    print Dumper(\@dividends2);
    $line[2] = $dividend_real;
    $line[7] = $dividend2_real;
    print OUT join(',',@line), qq(\n);
}
close(OUT);
close(IN);

