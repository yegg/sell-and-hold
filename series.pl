#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;
use Finance::Math::IRR;
use Statistics::Lite qw(mean stddev);

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
my $VALLEY_THRESHOLD = 1.10;

# Sell after this threshold off the peak,
# e.g. 0.80 means sell after a 20% correction.
my $SELL_THRESHOLD = 0.80;

# Capital gains rate. I didn't bother modeling this,
# since almost anything reasonable erases all the gains.
my $CAPITAL_GAINS = 0.999999999999;

# S&P time series.
my @s_and_p_series = get_s_and_p_series();

# Calculate earnings over MONTHS for each starting month.
my %series = calculate_earnings();


my @irr_buy_and_hold = ();
my @irr_timing = ();
my ($beats_count) = calculate_irr(\@irr_buy_and_hold, \@irr_timing);

print qq(\nTotal series: ), scalar(@irr_timing), qq(\n);
print qq(Timing beats Buy and Hold: $beats_count, ), sprintf("%0.2f",100*($beats_count/scalar(@irr_timing))), qq(\%\n);
print qq(Buy and Hold mean: ), sprintf("%0.2f",mean(@irr_buy_and_hold)), qq(\n);
print qq(Buy and Hold stddev: ), sprintf("%0.2f",stddev(@irr_buy_and_hold)), qq(\n);
print qq(Timing mean: ), sprintf("%0.2f",mean(@irr_timing)), qq(\n);
print qq(Timing stddev: ), sprintf("%0.2f",stddev(@irr_timing)), qq(\n);

sub calculate_irr {
    my ($irr_buy_and_hold_ref, $irr_timing_ref) = @_;

    my $beats_count = 0;

  SERIES: foreach my $series (sort {$a cmp $b} keys %series) {
        next SERIES if $series{$series}{'months'}<$MONTHS;
        next SERIES if $series ne $DEBUG_DATE && $DEBUG;
        
        my $start_date = $series;
        my $end_date = $series{$start_date}{'end_date'};
        my $start_price = $series{$start_date}{'start_price'};
        my $end_price = $series{$start_date}{'end_price'};
        my $dividend = $series{$start_date}{'dividend'};
        my $in_market = $series{$start_date}{'in_market'};
        my $market_count = $series{$start_date}{'market_count'};
        
        my %buy_cashflow = (
            $start_date => -$start_price,
            $end_date => ($end_price + $dividend)*$CAPITAL_GAINS
        );
        my $irr_buy_and_hold = xirr(%buy_cashflow, precision => 0.001) || 0;
        $irr_buy_and_hold = sprintf("%0.2f",100*$irr_buy_and_hold);
        
        my $sell_dates = '';
        my $sell_end_adj = 0;
        my $last_start_price = $start_price;
      MARKET: for (my $i=1; $i<=$market_count; $i++) {
            my $sell_start_date = $series{$start_date}{'market'}{$i}{'start_date'};
            my $sell_end_date = $series{$start_date}{'market'}{$i}{'end_date'};
            my $sell_start_price = $series{$start_date}{'market'}{$i}{'start_price'};
            my $sell_end_price = $series{$start_date}{'market'}{$i}{'end_price'};
            my $sell_dividend = $series{$start_date}{'market'}{$i}{'dividend'};
            
            next MARKET if !$sell_end_date;
            
            if ($DEBUG) {
                print qq(\n);
                print qq(series_start_date: $start_date\n);
                print qq(series_start_price: $start_price\n);
                print qq(sell_start_date: $sell_start_date\n);
                print qq(sell_end_date: $sell_end_date\n);
                print qq(last_start_price: $last_start_price\n);
                print qq(sell_start_price: $sell_start_price\n);
                print qq(sell_end_price: $sell_end_price\n);
                print qq(sell_dividend: $sell_dividend\n);
            }
            
            my $shares = $last_start_price / $sell_start_price;
            print qq(shares: $shares\n) if $DEBUG;
            
            my $sell_start_price_adj = $sell_start_price * $shares;
            my $sell_end_price_adj = $sell_end_price * $shares;
            my $sell_dividend_adj = $sell_dividend * $shares;
            my $sell_end_amt = ($sell_end_price_adj+$sell_dividend_adj)*$CAPITAL_GAINS;
            
            if ($DEBUG) {
                print qq(sell_start_price_adj: $sell_start_price_adj\n);
                print qq(sell_end_price_adj: $sell_end_price_adj\n);
                print qq(sell_dividend_adj: $sell_dividend_adj\n);
                print qq(sell_end_amt: $sell_end_amt\n);
            }
            
            $sell_end_adj += $sell_end_amt - $last_start_price;
            $last_start_price = $sell_end_amt;
            print qq(sell_end_adj: $sell_end_adj\n) if $DEBUG;
            
            $sell_dates .= qq(\n\t$sell_start_date\t$sell_end_date);
        }
        
        my $sell_interest = $series{$start_date}{'interest'};
        print qq(sell_interest: $sell_interest\n) if $DEBUG;
        $sell_end_adj += $sell_interest;
        
        my $irr_timing = 0;
        if ($sell_dates) {
            my %sell_cashflow = (
                $start_date => -$start_price,
                $end_date => $start_price + $sell_end_adj
            );
            $irr_timing = xirr(%sell_cashflow, precision => 0.001) || 0;
            $irr_timing = sprintf("%0.2f",100*$irr_timing);
        }        
        
        push(@{$irr_buy_and_hold_ref},$irr_buy_and_hold);
        push(@{$irr_timing_ref},$irr_timing);
        my $diff_irr = $irr_timing - $irr_buy_and_hold;
        $beats_count++ if $diff_irr>0;
        
        print qq(\n$start_date\t$end_date\t$irr_buy_and_hold$sell_dates\n\t$irr_timing\t$diff_irr\n);
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
            next if $series{$starting_date}{'months'}>$MONTHS;

            my $in_market = $series{$starting_date}{'in_market'} || 0;
            my $market_count = $series{$starting_date}{'market_count'} || 0;

            $series{$starting_date}{'months'}++;
            $series{$starting_date}{'dividend'}+=$dividend;

            if ($price>$series{$starting_date}{'peak'}) {
                $series{$starting_date}{'peak'} = $price;
                $series{$starting_date}{'valley'} = $price;
            }
            $series{$starting_date}{'valley'} = $price if $price<$series{$starting_date}{'valley'};

            if ($in_market) {
                $series{$starting_date}{'market'}{$market_count}{'dividend'}+=$dividend;
                $series{$starting_date}{'market'}{$market_count}{'peak'} = $price if $price>$series{$starting_date}{'market'}{$market_count}{'peak'};
            } else {
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
            if ($series{$starting_date}{'months'}==2 || 
                    (!$in_market && 
                        $price/$series{$starting_date}{'valley'} > $VALLEY_THRESHOLD)) {

                if ($DEBUG && $starting_date eq $DEBUG_DATE) {
                    print qq(\n\n\n\nJUMPING INTO MARKET ON $date\n\n\n\n);
                }

                $series{$starting_date}{'in_market'} = 1;
                $series{$starting_date}{'market_count'}++;
                $market_count = $series{$starting_date}{'market_count'};
                $series{$starting_date}{'valley'} = $price;
                $series{$starting_date}{'market'}{$market_count}{'peak'} = $price;
                $series{$starting_date}{'market'}{$market_count}{'start_price'} = $price;
                $series{$starting_date}{'market'}{$market_count}{'start_date'} = $date;
                $series{$starting_date}{'market'}{$market_count}{'dividend'} = $dividend;
            }

            # When to jump out of the market.
            if (1 && $in_market && 
                            $price/$series{$starting_date}{'market'}{$market_count}{'peak'} < $SELL_THRESHOLD) {

                if ($DEBUG && $starting_date eq $DEBUG_DATE) {
                    print qq(\n\n\n\nJUMPING OUT OF MARKET ON $date\n\n\n\n);
                }

                $series{$starting_date}{'in_market'} = 0;
                $series{$starting_date}{'market'}{$market_count}{'end_price'} = $price;
                $series{$starting_date}{'market'}{$market_count}{'end_date'} = $date;
            }

            if ($series{$starting_date}{'months'}==$MONTHS) {
                if ($in_market) {
                    $series{$starting_date}{'market'}{$market_count}{'end_price'} = $price;
                    $series{$starting_date}{'market'}{$market_count}{'end_date'} = $date;
                }
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
    LINE: while (my $line = <IN>) {
        chomp($line);
        my @line = split(/,/,$line);
        my $date = $line[0] || '';
        my $interest = $line [5] || '';
        my $price = $line [1] || '';
        my $dividend = $line [2] || '';

        next LINE if !$date || !$price || !$dividend;
        
        push(@series,$date,$price,$interest,$dividend/12);
    }
    close(IN);

    return @series;
}
