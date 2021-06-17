#!/usr/bin/env perl
use v5.26;
use utf8;
use feature 'signatures';

use Twitter::API;
use Text::CSV qw(csv);
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
    my $progress = latest_progress();
    my $date = $progress->{"date"};
    my $total_vaccinations = $progress->{"total_vaccinations"};
    my $dose1_cumulative_sum = $progress->{"people_vaccinated"};
    my $dose2_cumulative_sum = $progress->{"people_fully_vaccinated"};

    $date =~ s{/}{-}g;

    my $msg = "";
    if ($dose1_cumulative_sum && $dose2_cumulative_sum) {
        my @o = map { build_progress_bar($_, POPULATION_OF_TAIWAN) } ( $dose1_cumulative_sum, $dose2_cumulative_sum );
        $msg .= "第一劑 $dose1_cumulative_sum 人\n" .
            $o[0]{"bar"} . " " . $o[0]{"percentage"} . "\%\n\n" .
            "第二劑 $dose2_cumulative_sum 人\n" .
            $o[1]{"bar"} . " " . $o[1]{"percentage"} . "\%\n\n";
    } else {
        my $o = build_progress_bar($total_vaccinations, POPULATION_OF_TAIWAN);
        $msg .= "第一劑 + 第二劑\n" .
            $o->{"bar"} . " " . $o->{"percentage"} . "\%\n\n";
    }

    $msg .= "累計至 $date，全民共接種了 $total_vaccinations 劑\n" .
        "#CovidVaccine #COVID19 #COVID19Taiwan";
    return $msg;
}

sub build_progress_bar($n, $base) {
    my $percentage = 100 * $n / $base;
    my $width = 26;
    my $p = int $width * $percentage / 100;
    my $q = $width - $p;
    my $bar = "[" . ("#" x $p) . ("_" x $q) . "]";
    $percentage = int(1000 * $percentage) / 1000;
    return { "bar" => $bar, "percentage" => $percentage };
}

sub latest_progress {
    # my $url = "https://raw.githubusercontent.com/owid/covid-19-data/master/public/data/vaccinations/country_data/Taiwan.csv";
    my $url = "https://raw.githubusercontent.com/owid/covid-19-data/master/scripts/scripts/vaccinations/output/Taiwan.csv";
    my $res = Mojo::UserAgent->new->get($url)->result;
    $res->is_success or die "Failed to fetch: $url";

    my $body = $res->body;
    my $rows = csv( "in" => \$body, "headers" => "auto");
    return $rows->[-1];
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
        say "https://twitter.com/" . $r->{"user"}{"screen_name"} . "/status/" . $r->{id_str};
    } else {
        say "#=> Not tweeting";
    }
}
