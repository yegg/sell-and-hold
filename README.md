# Sell and Hold

This repo is about analyzing the Sell and Hold market strategy, explained in detail at [The Sell and Hold Strategy](https://medium.com/@yegg/the-sell-and-hold-strategy-d7ad0ab16647). It is used to produce the analysis presented in that article.

To execute the simulation, run:

```perl
perl sell_and_hold.pl
```

Simulation (and strategy) parameters are defined and explained at the top of that file. In addition, it can take some command line arguments which are currently used by sensitivity.pl to assist with quicker sensitivity analysis. To see an example of that, run:

```perl
perl sensitivity.pl
```

**Note:** The Perl script depends on the `Finance::Math::IRR` and `Statistics::Lite` modules. Read the [CPAN documentation](http://www.cpan.org/modules/INSTALL.html) for how to install Perl modules.

The data that the simulation draws on lives in data/. Enjoy! Pull requests are welcome.
