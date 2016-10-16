#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;
use Finance::Math::IRR;

# Num of months in the model.
my $MONTHS = (30 * 12)+1;

my $VALLEY_THRESHOLD = 1.10;
my $SELL_THRESHOLD = 0.80;
my $DEBUG = 0;
my $DEBUG_DATE = '1986-06-01';
my $CAPITAL_GAINS = 0.999999999999;

my $diff_count = 0;
my $diff_count2 = 0;

# S&P time series.
my @s_and_p_series = get_s_and_p_series();

# Calculate earnings over MONTHS for each starting month.
my %series = calculate_earnings();


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
    my $buy_irr = xirr(%buy_cashflow, precision => 0.001) || 0;
    $buy_irr = sprintf("%0.2f",100*$buy_irr);

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

    my $sell_irr = 0;
    if ($sell_dates) {
        my %sell_cashflow = (
            $start_date => -$start_price,
            $end_date => $start_price + $sell_end_adj
        );
        $sell_irr = xirr(%sell_cashflow, precision => 0.001) || 0;
        $sell_irr = sprintf("%0.2f",100*$sell_irr);
    }        

    my $diff_irr = $sell_irr - $buy_irr;
    $diff_count++;
    $diff_count2++ if $diff_irr>0;

    print qq(\n$start_date\t$end_date\t$buy_irr$sell_dates\n\t$sell_irr\t$diff_irr\n);
}

print qq(\ndiff_count: $diff_count\n);
print qq(diff_count2: $diff_count2\t), sprintf("%0.2f",100*($diff_count2/$diff_count)), "\n";


sub calculate_earnings() {
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
