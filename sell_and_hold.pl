#!/usr/bin/env perl

# This script tests a "Sell and Hold" strategy,
# against a traditional "Buy and Hold strategy.

use strict;
use warnings;
use Data::Dumper;
use Finance::Math::IRR;
use Statistics::Lite qw(mean stddev);
use Date::Calc qw (Delta_Days);
use Getopt::Long;

# Turn to 1 to get DEBUG messages.
# Add a starting series date to see more detail.
my $DEBUG = 1;
my $DEBUG_DATE = '1986-06-01';
#my $DEBUG_DATE = '1871-01-01';
#my $DEBUG_DATE = '1937-11-01';

# Num of years in the model.
my $YEARS = 30;
#$YEARS = 140;

# Buy after coming off the bottom by this amount,
# e.g. 1.10 means 10% off the valley.
my $VALLEY_THRESHOLD = 1.05;

# Sell after this threshold off the peak,
# e.g. 0.80 means sell after a 20% correction.
my $SELL_THRESHOLD = 0.80;

# Whether to include capital gains (1) or not (0).
my $is_capital_gains = 1;

# Whether to force a static capital gains rate of (x)% or not (0).
my $is_capital_gains_rate = 0;

# Whether to include transaciton costs (1) or not (0).
my $is_transaction_costs = 1;

# Whether we base the calculation off of nominal (1),
# or real (0) price and dividend values.
my $is_nominal = 0;

# Whether we add interest when we're out of the market (1).
# Default is 0 since it is more conservative, and I
# didn't bother making the interest payments correct over time.
my $is_interest = 0;

# Whether to include dividends (1) or not (0) in returns.
# Default is 1 since it is more conservative, and
# also more correct.
my $is_dividend = 1;

# Whether to include dividends (1) or not (0)
# in peak/valley threshold calculations.
my $is_dividends_in_threshold = 0;

# Whether to start immediately in the market (1) or not (0).
my $is_start_in_market = 1;

# Year we start at -- earliest is 1871.
#my $year_start = 1871;
my $year_start = 1950;

# Year we end at -- latest data is from 2016.
my $year_end = 2017;

# Whether to print out the individual series (1) or not (0).
my $is_print_series = 1;

# Override options via the command line.
GetOptions (
    'years=i' => \$YEARS,
    'valley_threshold=f' => \$VALLEY_THRESHOLD,
    'sell_threshold=f' => \$SELL_THRESHOLD,
);

# The extra one is so it lines up by month.
my $MONTHS = ($YEARS * 12)+1;

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
print qq(Buy and Hold STDDEV: ), sprintf("%0.2f",stddev(@irr_buy_and_hold)), qq(\%\n);
print qq(Timing mean: ), sprintf("%0.2f",mean(@irr_timing)), qq(\%\n);
print qq(Timing STDDEV: ), sprintf("%0.2f",stddev(@irr_timing)), qq(\%\n);
print qq(Diff means: ), sprintf("%0.2f",mean(@irr_timing) - mean(@irr_buy_and_hold)), qq(\%\n);
print qq(Timing length mean: ), sprintf("%0.2f",mean(@timing_length)), qq( yrs\n);
print qq(Timing length STDDEV: ), sprintf("%0.2f",stddev(@timing_length)), qq( yrs\n);
print qq(Timings mean: ), sprintf("%0.2f",mean(@timings)), qq( times\n);
print qq(Timings STDDEV: ), sprintf("%0.2f",stddev(@timings)), qq( times\n);


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

        # How much we give up in capital gains tax.
        my $end_capital_gains = calculate_capital_gains_tax($start_date,$end_date,$end_price-$start_price);
        $end_capital_gains = 0 if !$is_capital_gains || $end_capital_gains<0;

        # Increase start price by transaction costs.
        my $start_price_adj = $start_price;
        $start_price_adj += calculate_transaction_cost($start_date,$start_price_adj) if $is_transaction_costs;

        # Reduce end price by transaction costs.
        my $end_price_adj = $end_price;
        $end_price_adj -= calculate_transaction_cost($end_date,$end_price_adj) if $is_transaction_costs;

        # How much we made total.
        my $end_amt = $end_price_adj + $dividend;

        # IRR calculation for buy and hold.
        # Assumes we bought "1 share" of the market at the current price,
        # Then got cash back at the end price, plus any accrued dividends,
        # Then took capital gains.
        my %buy_and_hold_cashflow = (
            $start_date => -$start_price_adj,
            $end_date => $end_amt-$end_capital_gains
        );
        my $irr_buy_and_hold = xirr(%buy_and_hold_cashflow, precision => 0.001) || 0;
        $irr_buy_and_hold = sprintf("%0.2f",100*$irr_buy_and_hold);
        
        # Relative percentage gains for buy and hold session.
        my $buy_and_hold_rel = sprintf("%0.2f",100*($end_amt-$start_price)/$start_price);
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

            if ($DEBUG) {
                print qq(timing_start_price_adj: $timing_start_price_adj\n);
                print qq(timing_end_price_adj: $timing_end_price_adj\n);
                print qq(timing_dividend_adj: $timing_dividend_adj\n);
            }

            # Increase start price by transaction costs.
            $timing_start_price_adj += calculate_transaction_cost($timing_start_date,$timing_start_price_adj) if $is_transaction_costs;
            print qq(timing_start_price after transaction costs: $timing_start_price_adj\n) if $DEBUG;

            # Reduce end price by transaction costs.
            $timing_end_price_adj -= calculate_transaction_cost($timing_end_date,$timing_end_price_adj) if $is_transaction_costs;
            print qq(timing_end_price after transaction costs: $timing_end_price_adj\n) if $DEBUG;

            # When we sell we get back the adjusted end price plus dividends,
            my $timing_end_amt = $timing_end_price_adj+$timing_dividend_adj;

            # What we owe in capital gains.
            my $timing_end_capital_gains = calculate_capital_gains_tax($timing_start_date,$timing_end_date,$timing_end_price_adj-$last_start_price);
            $timing_end_capital_gains = 0 if !$is_capital_gains || $timing_end_capital_gains<0;

            if ($DEBUG) {
                print qq(timing_end_amt: $timing_end_amt\n);
                print qq(timing_end_capital_gains: $timing_end_capital_gains\n);
            }
            
            # For this round in the market, we actually made
            # what we ended with minus what we started with.
            my $timing_adj = $timing_end_amt - $last_start_price - $timing_end_capital_gains;
            print qq(timing_adj: $timing_adj\n) if $DEBUG;

            # Add to running total.
            $timing_end_adj += $timing_adj;
            print qq(timing_end_adj: $timing_end_adj\n) if $DEBUG;

            # IRR for this in-market session.
            my %timing_cashflow_tmp = (
                $timing_start_date => -$last_start_price,
                $timing_end_date => $timing_end_amt-$timing_end_capital_gains
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
            $timing_dates .= qq(\n\t$timing_start_date\t$timing_end_date\tIRR: $irr_timing_tmp\%\tABR: $timing_rel\%);

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
        
        print qq(\nBuy and Hold for $start_date to $end_date: $irr_buy_and_hold\% (ABR: $buy_and_hold_rel\%)\nTiming strategy: $irr_timing\% (DIFF: $diff_irr\%)$timing_dates\n) if $is_print_series;
    }

    return ($beats_count);
}


sub calculate_earnings {
    my %series = ();

    while (my $date = shift @s_and_p_series) {
        my $price = shift(@s_and_p_series);
        my $interest = shift(@s_and_p_series);
        my $dividend = shift(@s_and_p_series);
        my $price_adj = $price;
        
        # Update existing series.
        foreach my $starting_date (keys %series) {

            # Ignore series that have already completed.
            next if $series{$starting_date}{'months'}>=$MONTHS;

            # Are we in the market?
            my $in_market = $series{$starting_date}{'in_market'} || 0;

            # Index of which time we're in the market.
            my $market_count = $series{$starting_date}{'market_count'} || 0;

            # Add to overall time.
            $series{$starting_date}{'months'}++;

            # Add to running dividends.
            $series{$starting_date}{'dividend'}+=$dividend;

            # If using total returns, then adjust price accordingly.
            if ($is_dividends_in_threshold) {
                if ($in_market) {
                    $price_adj = $price + $series{$starting_date}{'market'}{$market_count}{'dividend'};
                } else {
                    $price_adj = $price + $series{$starting_date}{'dividend_out'};
                }
            }

            # If this is a new price peak in market, reset peak.
            $series{$starting_date}{'peak'} = $price_adj if $in_market && $price_adj>$series{$starting_date}{'peak'};

            # If this is a new valley out of market, reset valley.
            $series{$starting_date}{'valley'} = $price_adj if !$in_market && $price_adj<$series{$starting_date}{'valley'};

            # If this is a new in-market peak, reset peak.
            $series{$starting_date}{'market'}{$market_count}{'peak'} = $price_adj if $in_market && $price_adj>$series{$starting_date}{'market'}{$market_count}{'peak'};

            # Add to running interest.
            $series{$starting_date}{'interest'}+=$series{$starting_date}{'start_price'}*($interest/12)/100 if !$in_market;

            if ($DEBUG && $starting_date eq $DEBUG_DATE) {
                print qq(\n);
                print qq(date: $date\n);
                print qq(price: $price\n);
                print qq(price_adj: $price_adj\n);
                print qq(months: ), $series{$starting_date}{'months'}, qq(\n);
                print qq(in_market: $in_market\n);
                print qq(market_count: $market_count\n);
                
                if ($in_market) {
                    print qq(peak: ), $series{$starting_date}{'market'}{$market_count}{'peak'}, qq(\n);
                    print qq(start_price: ), $series{$starting_date}{'market'}{$market_count}{'start_price'}, qq(\n);
                    print qq(peak threshold: ), $price_adj/$series{$starting_date}{'market'}{$market_count}{'peak'}, qq(\n);

                } else {
                    print qq(peak: ), $series{$starting_date}{'peak'}, qq(\n);
                    print qq(peak threshold: ), $price_adj/$series{$starting_date}{'peak'}, qq(\n);
                }

                print qq(valley: ), $series{$starting_date}{'valley'}, qq(\n);
                print qq(valley threshold: ), $price_adj/$series{$starting_date}{'valley'}, qq( vs $VALLEY_THRESHOLD\n);
            }

            # When to jump in the market.
            if (!$in_market) {

                # The current price relative to the last valley is above our threhsold.
                if ($price_adj/$series{$starting_date}{'valley'} > $VALLEY_THRESHOLD) {

                    if ($DEBUG && $starting_date eq $DEBUG_DATE) {
                        print qq(\n\n\n\nJUMPING INTO MARKET ON $date\n\n\n\n);
                    }
                    
                    # Mark that we're now in the market.
                    $series{$starting_date}{'in_market'} = 1;
                    $in_market = 1;
                    
                    # Increment the in-market counter and update our index variable.
                    $series{$starting_date}{'market_count'}++;
                    $market_count = $series{$starting_date}{'market_count'};
                    
                    # Reset the peak & valley to the current price.
                    $series{$starting_date}{'valley'} = $price_adj;
                    $series{$starting_date}{'peak'} = $price_adj;
                    
                    # Initilize in-market variables.
                    $series{$starting_date}{'market'}{$market_count}{'peak'} = $price_adj;
                    $series{$starting_date}{'market'}{$market_count}{'start_price'} = $price;
                    $series{$starting_date}{'market'}{$market_count}{'start_date'} = $date;
                    $series{$starting_date}{'market'}{$market_count}{'dividend'} = $dividend;
                }
            }

            # When to jump out of the market.
            # If we're already in the market,
            if ($in_market) {

                # The price relative to the in-market peak has dropped below our threshold.
                if ($price_adj/$series{$starting_date}{'market'}{$market_count}{'peak'} < $SELL_THRESHOLD) {

                    if ($DEBUG && $starting_date eq $DEBUG_DATE) {
                        print qq(\n\n\n\nJUMPING OUT OF MARKET ON $date\n\n\n\n);
                    }

                    # Mark that we're now out of the market.
                    $series{$starting_date}{'in_market'} = 0;

                    # Record the ending in-market price and date.
                    $series{$starting_date}{'market'}{$market_count}{'end_price'} = $price;
                    $series{$starting_date}{'market'}{$market_count}{'end_date'} = $date;

                    # Reset the peak & valley to the current price.
                    $series{$starting_date}{'valley'} = $price_adj;
                    $series{$starting_date}{'peak'} = $price_adj;
                    $series{$starting_date}{'dividend_out'} = 0 if $is_dividends_in_threshold;
                }
            }                

            # If we reached the end of our time window.
            if ($series{$starting_date}{'months'}==$MONTHS) {

                if ($DEBUG && $starting_date eq $DEBUG_DATE) {
                    print qq(\n\n\n\nEND OF SERIES ON $date\n\n\n\n);
                }

                # If we're currently in the market, record the ending in-market price and date.
                if ($in_market) {
                    $series{$starting_date}{'market'}{$market_count}{'end_price'} = $price;
                    $series{$starting_date}{'market'}{$market_count}{'end_date'} = $date;
                }

                # Record the overall ending price and date.
                $series{$starting_date}{'end_price'} = $price;
                $series{$starting_date}{'end_date'} = $date;


                # We are going out.
                $series{$starting_date}{'in_market'} = 0;
                $in_market = 0;
            }

            # Add to running dividends when out of market.
            $series{$starting_date}{'dividend_out'}+=$dividend if !$in_market;

            # Record in-market dividends.
            $series{$starting_date}{'market'}{$market_count}{'dividend'}+=$dividend if $in_market;
        }
        
        # Add new series.
        $series{$date} = ();
        $series{$date}{'months'} = 1;
        $series{$date}{'peak'} = $price_adj;
        $series{$date}{'valley'} = $price_adj;
        $series{$date}{'start_price'} = $price;
        $series{$date}{'dividend'} = $dividend;
        $series{$date}{'interest'} = 0;

        # Start in the market.
        if ($is_start_in_market) {

            # Let the model know we're in the market.
            $series{$date}{'in_market'} = 1;

            # Increment the in-market counter and update our index variable.
            $series{$date}{'market_count'}++;
            my $market_count = $series{$date}{'market_count'};
            
            # Set the valley to the current price.
            $series{$date}{'valley'} = $price;
            
            # Initilize in-market variables.
            $series{$date}{'market'}{$market_count}{'peak'} = $price_adj;
            $series{$date}{'market'}{$market_count}{'start_price'} = $price;
            $series{$date}{'market'}{$market_count}{'start_date'} = $date;
            $series{$date}{'market'}{$market_count}{'dividend'} = $dividend;
            
        } else {
            $series{$date}{'in_market'} = 0;
            $series{$date}{'market_count'} = 0;
        }

    }

    return %series;
}

# Read in S&P data into a time series.
sub get_s_and_p_series {

    my @series = ();

    # https://github.com/datasets/s-and-p-500/tree/master/scripts
    open (IN,"<data/s-and-p-500.adj.csv");
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
        
        # Reduce dividends by the dividend tax.
        my ($year) = $date =~ /^(\d+)\-/;
        $dividend -= calculate_dividend_tax($year,$dividend) if $is_capital_gains;

        push(@series,$date,$price,$interest,$dividend);
    }
    close(IN);

    return @series;
}

# Calculate capital gains tax.
{

    my $is_rates_loaded = 0;
    my %capital_gains_rates = ();

    sub get_capital_gains_rates {

        open(IN,"<data/capital_gains_max_tax_rates.csv");
        <IN>;
        while (my $line = <IN>) {
            chomp($line);
            my @line = split(/,/,$line);
            my $year = $line[0];
            my $long_term = $line[1]/100;
            my $short_term = $line[2]/100;
            
            $capital_gains_rates{$year}{'long_term'} = $long_term;
            $capital_gains_rates{$year}{'short_term'} = $short_term;
        }
        close(IN);
    }        

    sub calculate_capital_gains_tax {
        my ($start_date, $end_date, $gain) = @_;

        if (!$is_rates_loaded) {
            get_capital_gains_rates();
            $is_rates_loaded = 1;
        }

        my $is_long_term = 0;
        my $year_gain = '';
        {
            my ($syear,$smonth,$sday) = $start_date =~ /^(\d+)\-(\d+)\-(\d+)/;
            my ($eyear,$emonth,$eday) = $end_date =~ /^(\d+)\-(\d+)\-(\d+)/;
            my $Dd = Delta_Days($syear,$smonth,$sday,
                                $eyear,$emonth,$eday);

            # If holding period is greater than 365 days, use long term rate.
            $is_long_term = 1 if $Dd>365;
            $year_gain = $eyear; 
            print qq(year_gain: $year_gain\n) if $DEBUG;
        }

        # Get rate.
        my $capital_gains_rate = $is_long_term ? $capital_gains_rates{$year_gain}{'long_term'} : $capital_gains_rates{$year_gain}{'short_term'};
        $capital_gains_rate = $is_capital_gains_rate if $is_capital_gains_rate;
        print qq(capital_gains_rate: ), (100*$capital_gains_rate), qq(\%\n) if $DEBUG;

        # Calculate amount.
        my $capital_gains_amt = $gain * $capital_gains_rate;

        return $capital_gains_amt;
    }
}

# Calculate dividends tax.
{

    my $is_rates_loaded = 0;
    my %dividend_tax_rates = ();

    sub get_dividend_tax_rates {

        open(DIV,"<data/dividend_max_tax_rates.csv");
        <DIV>;
        while (my $line = <DIV>) {
            chomp($line);
            my @line = split(/,/,$line);
            my $year = $line[0];
            my $rate = $line[1]/100;
            
            $dividend_tax_rates{$year} = $rate
        }
        close(DIV);
    }        

    sub calculate_dividend_tax {
        my ($year, $gain) = @_;

        if (!$is_rates_loaded) {
            get_dividend_tax_rates();
            $is_rates_loaded = 1;
        }

        # Get rate.
        my $dividend_rate = $dividend_tax_rates{$year} || 0;
        #print qq(dividend_rate: ), (100*$dividend_rate), qq(\%\n) if $DEBUG;

        # Calculate amount.
        my $dividend_tax_amt = $gain * $dividend_rate;

        return $dividend_tax_amt;
    }
}


# Calculate transaction costs.
{

    my $is_rates_loaded = 0;
    my %transaction_cost_rates = ();

    sub get_transaction_cost_rates {

        open(DIV,"<data/transction_cost_rates.csv");
        <DIV>;
        while (my $line = <DIV>) {
            chomp($line);
            my @line = split(/,/,$line);
            my $year = $line[0];
            my $rate = $line[1]/100;
            
            $transaction_cost_rates{$year} = $rate
        }
        close(DIV);
    }        

    sub calculate_transaction_cost {
        my ($date, $amt) = @_;

        if (!$is_rates_loaded) {
            get_transaction_cost_rates();
            $is_rates_loaded = 1;
        }

        # Get year.
        my ($year) = $date =~ /^(\d+)-/;

        # Get rate.
        my $transaction_cost_rate = $transaction_cost_rates{$year} || 0;
        print qq(transaction_cost_rate: ), (100*$transaction_cost_rate), qq(\%\n) if $DEBUG;

        # Calculate amount.
        my $transaction_cost_amt = $amt * $transaction_cost_rate;

        return $transaction_cost_amt;
    }
}
