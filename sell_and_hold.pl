#!/usr/bin/env perl

# This script tests a "Sell and Hold" strategy,
# against a traditional "Buy and Hold strategy.

use strict;
use warnings;
use Data::Dumper;
use Finance::Math::IRR;
use Statistics::Lite qw(mean stddev);
use Date::Calc qw (Delta_Days);

# Turn to 1 to get DEBUG messages.
# Add a starting series date to see more detail.
my $DEBUG = 0;
my $DEBUG_DATE = '1986-06-01';

# Num of months in the model.
# The starting number is years.
# The extra one is so it lines up by month.
my $MONTHS = (30 * 12)+1;

# Buy after coming off the bottom by this amount,
# e.g. 1.10 means 10% off the valley.
my $VALLEY_THRESHOLD = 1.05;

# Sell after this threshold off the peak,
# e.g. 0.80 means sell after a 20% correction.
my $SELL_THRESHOLD = 0.80;

# Capital gains you get to keep. 1 means all.
# I didn't bother modeling this over time,
# since almost anything reasonable erases all the gains.
my $CAPITAL_GAINS = 1;

# Whether we base the calculation off of nominal (1),
# or real (0) price and dividend values.
my $is_nominal = 1;

# Whether we add interest when we're out of the market (1).
# Default is 0 since it is more conservative, and I
# didn't bother making the interest payments correct over time.
my $is_interest = 0;

# Whether to include dividends (1) or not (0).
# Default is 1 since it is more conservative, and
# also more correct.
my $is_dividend = 1;

# Year we start at -- earliest is 1871.
my $year_start = 1871;

# Year we end at -- latest data is from 2016.
my $year_end = 2017;

# Whether to print out the individual series (1) or not (0).
my $is_print_series = 1;

# S&P time series.
my @s_and_p_series = get_s_and_p_series();

# Calculate earnings over MONTHS for each starting month.
my %series = calculate_earnings();

# Internal rate of returns for each strategy.
my @irr_buy_and_hold = ();
my @irr_timing = ();
my @timings = (); 
my @timing_length = (); 
my ($beats_count) = calculate_irr(\@irr_buy_and_hold, \@irr_timing, \@timings, \@timing_length);

print qq(\nTotal series: ), scalar(@irr_timing), qq(\n);
print qq(Timing beats Buy and Hold: $beats_count, ), sprintf("%0.2f",100*($beats_count/scalar(@irr_timing))), qq(\%\n);
print qq(Buy and Hold mean: ), sprintf("%0.2f",mean(@irr_buy_and_hold)), qq(\%\n);
print qq(Buy and Hold stddev: ), sprintf("%0.2f",stddev(@irr_buy_and_hold)), qq(\%\n);
print qq(Timing mean: ), sprintf("%0.2f",mean(@irr_timing)), qq(\%\n);
print qq(Timing stddev: ), sprintf("%0.2f",stddev(@irr_timing)), qq(\%\n);
print qq(Timing length mean: ), sprintf("%0.2f",mean(@timing_length)), qq( yrs\n);
print qq(Timing length stddev: ), sprintf("%0.2f",stddev(@timing_length)), qq( yrs\n);
print qq(Timings mean: ), sprintf("%0.2f",mean(@timings)), qq( times\n);
print qq(Timings stddev: ), sprintf("%0.2f",stddev(@timings)), qq( times\n);


# Uses calculated earnings to calculate IRRs for each strategy.
sub calculate_irr {
    my ($irr_buy_and_hold_ref, $irr_timing_ref, $timings_ref, $timing_length_ref) = @_;

    # The number of times the timing strategy beats the buy and hold strategy.
    my $beats_count = 0;

  SERIES: foreach my $series (sort {$a cmp $b} keys %series) {

        # Ignore series shorter than our window.
        next SERIES if $series{$series}{'months'}<$MONTHS;

        # For debugging a specific series.
        next SERIES if $series ne $DEBUG_DATE && $DEBUG;
        
        # Beginning of series.
        my $start_date = $series;

        # End of series.
        my $end_date = $series{$start_date}{'end_date'};

        # First market price.
        my $start_price = $series{$start_date}{'start_price'};

        # Last market price.
        my $end_price = $series{$start_date}{'end_price'};

        # The amount we made from dividends.
        my $dividend = $is_dividend ? $series{$start_date}{'dividend'} : 0;

        # How many times we were in the market.
        my $market_count = $series{$start_date}{'market_count'};
        push(@{$timings_ref},$market_count);
        
        # IRR calculation for buy and hold.
        # Assumes we bought "1 share" of the market at the current price,
        # Then got cash back at the end price, plus any accrued dividends,
        # Then took capital gains.
        my %buy_and_hold_cashflow = (
            $start_date => -$start_price,
            $end_date => ($end_price + $dividend)*$CAPITAL_GAINS
        );
        my $irr_buy_and_hold = xirr(%buy_and_hold_cashflow, precision => 0.001) || 0;
        $irr_buy_and_hold = sprintf("%0.2f",100*$irr_buy_and_hold);
        
        # Relative percentage gains for buy and hold session.
        my $buy_and_hold_rel = sprintf("%0.2f",100*(($end_price+$dividend)-$start_price)/$start_price);
        print qq(buy_and_hold_rel: $buy_and_hold_rel\%\n) if $DEBUG;

        # For printing out which dates we were in the market.
        my $timing_dates = ''; 

        # For calculating how much we deviated from buy and hold.
        my $timing_end_adj = 0; 

        # How much we last exited the market at.
        my $last_start_price = $start_price; 

        # Each time we entered the market in the timing strategy.
      MARKET: for (my $i=1; $i<=$market_count; $i++) {

            # In market start and end dates and prices.
            my $timing_start_date = $series{$start_date}{'market'}{$i}{'start_date'};
            my $timing_end_date = $series{$start_date}{'market'}{$i}{'end_date'};
            my $timing_start_price = $series{$start_date}{'market'}{$i}{'start_price'};
            my $timing_end_price = $series{$start_date}{'market'}{$i}{'end_price'};

            # How much we made in dividends when in the market.
            my $timing_dividend = $is_dividend ? $series{$start_date}{'market'}{$i}{'dividend'} : 0;
            
            # TK
            next MARKET if !$timing_end_date;
            
            if ($DEBUG) {
                print qq(\n);
                print qq(timing_start_date: $timing_start_date\n);
                print qq(timing_end_date: $timing_end_date\n);
                print qq(last_start_price: $last_start_price\n);
                print qq(timing_start_price: $timing_start_price\n);
                print qq(timing_end_price: $timing_end_price\n);
                print qq(timing_dividend: $timing_dividend\n);
            }
            
            # Because we have windows where we are out of the market, 
            # the dollars we had when we started or last sold are different
            # from the current price, so we buy a number of "shares" in the market.
            my $shares = $last_start_price / $timing_start_price;
            print qq(shares: $shares\n) if $DEBUG;
            
            # We then adkust the prices and dividends based on our share amount.
            my $timing_start_price_adj = $timing_start_price * $shares;
            my $timing_end_price_adj = $timing_end_price * $shares;
            my $timing_dividend_adj = $timing_dividend * $shares;

            # When we sell we get back the adjusted end price,
            # plus dividends, less capital gains.
            my $timing_end_amt = ($timing_end_price_adj+$timing_dividend_adj)*$CAPITAL_GAINS;
            
            if ($DEBUG) {
                print qq(timing_start_price_adj: $timing_start_price_adj\n);
                print qq(timing_end_price_adj: $timing_end_price_adj\n);
                print qq(timing_dividend_adj: $timing_dividend_adj\n);
                print qq(timing_end_amt: $timing_end_amt\n);
            }
            
            # For this round in the market, we actually made
            # what we ended with minus what we started with.
            my $timing_adj = $timing_end_amt - $last_start_price;
            print qq(timing_adj: $timing_adj\n) if $DEBUG;

            # Add to running total.
            $timing_end_adj += $timing_adj;
            print qq(timing_end_adj: $timing_end_adj\n) if $DEBUG;

            # IRR for this in-market session.
            my %timing_cashflow_tmp = (
                $timing_start_date => -$last_start_price,
                $timing_end_date => $timing_end_amt
            );
            my $irr_timing_tmp = xirr(%timing_cashflow_tmp, precision => 0.001) || 0;
            $irr_timing_tmp = sprintf("%0.2f",100*$irr_timing_tmp);
            print qq(irr_timing_tmp: $irr_timing_tmp\n) if $DEBUG;

            # Relative percentage gains for this in-market session.
            my $timing_rel = sprintf("%0.2f",100*($timing_end_amt-$last_start_price)/$last_start_price);
            print qq(timing_rel: $timing_rel\n) if $DEBUG;

            # Calculate length of time we were in the market.
            {
                my ($syear,$smonth,$sday) = $timing_start_date =~ /^(\d+)\-(\d+)\-(\d+)/;
                my ($eyear,$emonth,$eday) = $timing_end_date =~ /^(\d+)\-(\d+)\-(\d+)/;
                my $Dd = Delta_Days($syear,$smonth,$sday,
                                 $eyear,$emonth,$eday);
                print qq(Dd: $Dd\n) if $DEBUG;
                push(@{$timing_length_ref},$Dd/365);
            }

            # Print out market in dates.
            $timing_dates .= qq(\n\t$timing_start_date\t$timing_end_date\tIRR: $irr_timing_tmp\%\tREL: $timing_rel\%);

            # Record what we ended with so we can go into the market
            # with that amount next time.
            $last_start_price = $timing_end_amt;
        }
        
        # The interest we made when out of the market.
        my $timing_interest = $is_interest ? $series{$start_date}{'interest'} : 0;
        print qq(timing_interest: $timing_interest\n) if $DEBUG;
        $timing_end_adj += $timing_interest;
        
        # The IRR of the timing stategy also starts with an outlay of the 
        # the start price at the start date. At the end though we get
        # that back plus whatever we made while in the market.
        my $irr_timing = 0;
        if ($timing_dates) {
            my %timing_cashflow = (
                $start_date => -$start_price,
                $end_date => $start_price + $timing_end_adj
            );
            $irr_timing = xirr(%timing_cashflow, precision => 0.001) || 0;
            $irr_timing = sprintf("%0.2f",100*$irr_timing);
        }        

        # Add the IRRs for this series for future stats.
        push(@{$irr_buy_and_hold_ref},$irr_buy_and_hold);
        push(@{$irr_timing_ref},$irr_timing);
        my $diff_irr = $irr_timing - $irr_buy_and_hold;
        $beats_count++ if $diff_irr>0;
        
        print qq(\nBuy and Hold for $start_date to $end_date: $irr_buy_and_hold\% (REL: $buy_and_hold_rel\%)\nTiming strategy: $irr_timing\% (DIFF: $diff_irr\%)$timing_dates\n) if $is_print_series;
    }

    return ($beats_count);
}


sub calculate_earnings {
    my %series = ();

    while (my $date = shift @s_and_p_series) {
        my $price = shift(@s_and_p_series);
        my $interest = shift(@s_and_p_series);
        my $dividend = shift(@s_and_p_series);
        
        # Update existing series.
        foreach my $starting_date (keys %series) {

            # Ignore series that have already completed.
            next if $series{$starting_date}{'months'}>$MONTHS;

            # Are we in the market?
            my $in_market = $series{$starting_date}{'in_market'} || 0;

            # Index of which time we're in the market.
            my $market_count = $series{$starting_date}{'market_count'} || 0;

            # Add to overall time.
            $series{$starting_date}{'months'}++;

            # Add to running dividends.
            $series{$starting_date}{'dividend'}+=$dividend;

            # If this is a new price peak, reset peak and valley.
            if ($price>$series{$starting_date}{'peak'}) {
                $series{$starting_date}{'peak'} = $price;
                $series{$starting_date}{'valley'} = $price;
            }

            # If this is a new valley, reset valley.
            $series{$starting_date}{'valley'} = $price if $price<$series{$starting_date}{'valley'};
            
            # If we're in the market.
            if ($in_market) {

                # Record in-market dividends.
                $series{$starting_date}{'market'}{$market_count}{'dividend'}+=$dividend;

                # If this is a new in-market peak, reset peak.
                $series{$starting_date}{'market'}{$market_count}{'peak'} = $price if $price>$series{$starting_date}{'market'}{$market_count}{'peak'};

            # If we're not in the market.
            } else {

                # Add to running interest.
                $series{$starting_date}{'interest'}+=$series{$starting_date}{'start_price'}*($interest/12)/100;
            }

            if ($DEBUG && $starting_date eq $DEBUG_DATE) {
                print qq(\n);
                print qq(date: $date\n);
                print qq(price: $price\n);
                
                if ($in_market) {
                    print qq(peak: ), $series{$starting_date}{'market'}{$market_count}{'peak'}, qq(\n);
                    print qq(start_price: ), $series{$starting_date}{'market'}{$market_count}{'start_price'}, qq(\n);
                    print qq(peak threshold: ), $price/$series{$starting_date}{'market'}{$market_count}{'peak'}, qq(\n);
                } else {
                    print qq(peak: ), $series{$starting_date}{'peak'}, qq(\n);
                    print qq(peak threshold: ), $price/$series{$starting_date}{'peak'}, qq(\n);
                }

                print qq(valley: ), $series{$starting_date}{'valley'}, qq(\n);
                print qq(valley threshold: ), $price/$series{$starting_date}{'valley'}, qq( vs $VALLEY_THRESHOLD\n);
            }

            # When to jump in the market.
            # If this is the first month (2 beause we already incremented above),
            if ($series{$starting_date}{'months'}==2 || 

                    # OR we're not already in the market.
                    (!$in_market && 

                         # AND the current price relative to the last valley is above our threhsold.
                        $price/$series{$starting_date}{'valley'} > $VALLEY_THRESHOLD)) {

                if ($DEBUG && $starting_date eq $DEBUG_DATE) {
                    print qq(\n\n\n\nJUMPING INTO MARKET ON $date\n\n\n\n);
                }

                # Mark that we're now in the market.
                $series{$starting_date}{'in_market'} = 1;

                # Increment the in-market counter and update our index variable.
                $series{$starting_date}{'market_count'}++;
                $market_count = $series{$starting_date}{'market_count'};

                # Reset the valley to the current price.
                $series{$starting_date}{'valley'} = $price;

                # Initilize in-market variables.
                $series{$starting_date}{'market'}{$market_count}{'peak'} = $price;
                $series{$starting_date}{'market'}{$market_count}{'start_price'} = $price;
                $series{$starting_date}{'market'}{$market_count}{'start_date'} = $date;
                $series{$starting_date}{'market'}{$market_count}{'dividend'} = $dividend;
            }

            # When to jump out of the market.
            # If we're already in the market,
            if ($in_market && 

                    # AND the price relative to the in-market peak has dropped below our threshold.
                    $price/$series{$starting_date}{'market'}{$market_count}{'peak'} < $SELL_THRESHOLD) {

                if ($DEBUG && $starting_date eq $DEBUG_DATE) {
                    print qq(\n\n\n\nJUMPING OUT OF MARKET ON $date\n\n\n\n);
                }

                # Mark that we're now out of the market.
                $series{$starting_date}{'in_market'} = 0;

                # Record the ending in-market price and date.
                $series{$starting_date}{'market'}{$market_count}{'end_price'} = $price;
                $series{$starting_date}{'market'}{$market_count}{'end_date'} = $date;
            }

            # If we reached the end of our time window.
            if ($series{$starting_date}{'months'}==$MONTHS) {

                # If we're currently in the market, record the ending in-market price and date.
                if ($in_market) {
                    $series{$starting_date}{'market'}{$market_count}{'end_price'} = $price;
                    $series{$starting_date}{'market'}{$market_count}{'end_date'} = $date;
                }

                # Record the overall ending price and date.
                $series{$starting_date}{'end_price'} = $price;
                $series{$starting_date}{'end_date'} = $date;
            }
        }
        
        # Add new series.
        $series{$date} = ();
        $series{$date}{'months'} = 1;
        $series{$date}{'peak'} = $price;
        $series{$date}{'valley'} = $price;
        $series{$date}{'start_price'} = $price;
        $series{$date}{'dividend'} = $dividend;
        $series{$date}{'in_market'} = 0;
        $series{$date}{'market_count'} = 0;
        $series{$date}{'interest'} = 0;
    }

    return %series;
}

# Read in S&P data into a time series.
sub get_s_and_p_series {

    my @series = ();

    # https://github.com/datasets/s-and-p-500/tree/master/scripts
    open (IN,"<../s-and-p-500/data/data.csv");
    <IN>;

    my $is_cutoff = 0;

    LINE: while (my $line = <IN>) {
        chomp($line);
        my @line = split(/,/,$line);
        my $date = $line[0] || '';

        $is_cutoff = 1 if !$is_cutoff && $date =~ /^$year_start/;
        next LINE if !$is_cutoff;

        last LINE if $date =~ /^$year_end/;

        my $interest = $line [5] || '';
        my $price = $line [1] || '';
        my $dividend = $line [2] || '';
        if (!$is_nominal) {
            $price = $line [6] || '';
            $dividend = $line [7] || '';
        }

        next LINE if !$date || !$price || !$dividend;
        
        push(@series,$date,$price,$interest,$dividend/12);
    }
    close(IN);

    return @series;
}
