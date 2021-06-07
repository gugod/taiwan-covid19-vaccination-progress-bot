#!/usr/bin/env perl
use v5.26;
use utf8;
use feature 'signatures';

use Twitter::API;
use YAML ();
use Encode ('encode_utf8');
use Getopt::Long ('GetOptionsFromArray');
use Mojo::UserAgent;

use constant {
    # Number https://zh.wikipedia.org/wiki/%E8%87%BA%E7%81%A3%E4%BA%BA%E5%8F%A3
    POPULATION_OF_TAIWAN => 23514196,
};

sub main {
    my @args = @_;

    my %opts;
    GetOptionsFromArray(
        \@args,
        \%opts,
        'c=s',
        'y|yes'
    ) or die("Error in arguments, but I'm not telling you what it is.");

    my $msg = build_message();
    maybe_tweet_update(\%opts, $msg);

    return 0;
}

exit(main(@ARGV));

sub build_message {
    my $p = people_vaccinated();
    my ($bar, $percentage) = build_progress_bar($p, POPULATION_OF_TAIWAN);
    $percentage = int(10 * $percentage) / 10;
    return $bar . " " . $percentage . '%';
}

sub build_progress_bar($n, $base) {
    my $percentage = 100 * $n / $base;
    my $width = 26;
    my $p = int $width * $percentage / 100;
    my $q = $width - $p;
    my $bar = "[" . ("#" x $p) . ("_" x $q) . "]";
    return ($bar, $percentage)
}

sub people_vaccinated {
    my $url = "https://raw.githubusercontent.com/owid/covid-19-data/master/public/data/vaccinations/country_data/Taiwan.csv";
    my $res = Mojo::UserAgent->new->get($url)->result;
    $res->is_success or die "Failed to fetch: $url";
    my @lines = split /\n/, $res->body;
    my @columns = split /,/, $lines[-1]; # yes, it works correctly for this particular csv.
    return $columns[4];
}

sub maybe_tweet_update ($opts, $msg) {
    unless ($msg) {
        say "# Message is empty.";
        return;
    }

    my $config;

    if ($opts->{c} && -f $opts->{c}) {
        say "[INFO] Loading config from $opts->{c}";
        $config = YAML::LoadFile( $opts->{c} );
    } elsif ($opts->{'github-secret'} && $ENV{'TWITTER_TOKENS'}) {
        say "[INFO] Loading config from env";
        $config = YAML::Load($ENV{'TWITTER_TOKENS'});
    } else {
        say "[INFO] No config.";
    }

    say "# Message";
    say "-------8<---------";
    say encode_utf8($msg);
    say "------->8---------";

    if ($opts->{y} && $config) {
        say "#=> Tweet for real";
        my $twitter = Twitter::API->new_with_traits(
            traits => "Enchilada",
            consumer_key        => $config->{consumer_key},
            consumer_secret     => $config->{consumer_secret},
            access_token        => $config->{access_token},
            access_token_secret => $config->{access_token_secret},
        );

        my $r = $twitter->update($msg);
        say "https://twitter.com/TWReservoir_bot/status/" . $r->{id_str};
    } else {
        say "#=> Not tweeting";
    }
}
