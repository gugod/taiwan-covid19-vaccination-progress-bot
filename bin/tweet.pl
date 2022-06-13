#!/usr/bin/env perl
use v5.36;
use utf8;

use Twitter::API;
use Mastodon::Client;
use Text::CSV qw(csv);
use YAML ();
use Encode ('encode_utf8');
use Getopt::Long ('GetOptionsFromArray');
use Mojo::UserAgent;
use Mojo::Date;
use Mojo::File;

use constant {
    # Find the updates of this stat from: https://www.ris.gov.tw/app/portal/2121
    #
    # As of the end of May, 2022.
    # Number from:
    # - https://www.ris.gov.tw/app/portal/2121?sn=22161403
    POPULATION_OF_TAIWAN => 23196178,
};

sub commify($num) {
    my $i = (length($num) % 3) || 3;
    my $num_commified = substr($num, 0, $i);
    while ($i < length($num)) {
        $num_commified .= "," . substr($num, $i, 3);
        $i += 3;
    }
    return $num_commified;
}

sub rounded($num) {
    sprintf('%.2f', $num)
}

sub main {
    my @args = @_;

    my %opts;
    GetOptionsFromArray(
        \@args,
        \%opts,
        'twitter-config=s',
        'mastodon-config=s',
        'y|yes',
        'fake-today=s',
        'csv-file=s',
        'csv-url=s',
    ) or die("Error in arguments, but I'm not telling you what it is.");

    my $msg = build_message(\%opts);
    maybe_post_update(\%opts, $msg);

    return 0;
}

exit(main(@ARGV));

sub today {
    my ($year, $mon, $day) = (localtime())[5,4,3];
    return sprintf('%04d-%02d-%02d', ($year + 1900), ($mon + 1), $day);
}

sub date_diff ($date1, $date2) {
    my $d1 = Mojo::Date->new($date1 . "T00:00:00Z");
    my $d2 = Mojo::Date->new($date2 . "T00:00:00Z");
    return int ($d1->epoch - $d2->epoch) / 86400;
}

sub build_message ($opts) {
    my $full_progress = full_progress($opts);

    my $latest = $full_progress->[-1];
    my $previous = $full_progress->[-2];

    my $date = $latest->{"date"};
    my $total_vaccinations = $latest->{"total_vaccinations"};
    my $dose1_cumulative_sum = $latest->{"people_vaccinated"};
    my $dose2_cumulative_sum = $latest->{"people_fully_vaccinated"};
    my $booster_cumulative_sum = $latest->{"total_boosters"};

    my $today = $opts->{"fake-today"} || today();
    if (date_diff($today, $date) != 1) {
        return "";
    }

    my $msg = "累計至 $date\n\n";

    if ($dose1_cumulative_sum && $dose2_cumulative_sum) {
        my ($dose1_increase, $dose2_increase);
        if (date_diff($date, $previous->{"date"}) == 1) {
            $dose1_increase = $dose1_cumulative_sum - $previous->{"people_vaccinated"};
            $dose2_increase = $dose2_cumulative_sum - $previous->{"people_fully_vaccinated"};
        }
        $msg .= dose_stats_and_bar("💉第一劑", $dose1_cumulative_sum, $dose1_increase);
        $msg .= dose_stats_and_bar("💉第二劑", $dose2_cumulative_sum, $dose2_increase);
    } else {
        $msg .= dose_stats_and_bar("💉第一劑 + 第二劑", $total_vaccinations, undef);
    }

    if ($booster_cumulative_sum) {
        my $booster_increase;
        if (date_diff($date, $previous->{"date"}) == 1) {
            $booster_increase = $booster_cumulative_sum - $previous->{"total_boosters"};
        }
        $msg .= dose_stats_and_bar("💉基礎加強劑 + 追加劑", $booster_cumulative_sum, $booster_increase);
    }

    $msg .= "#CovidVaccine #COVID19 #COVID19Taiwan";
    return $msg;
}

sub dose_stats_and_bar($label, $cumulative_sum, $increase) {
    return dose_stats($label, $cumulative_sum, $increase) ."\n".
        dose_bar($cumulative_sum) . "\n\n";
}

sub dose_stats($label, $cumulative_sum, $increase) {
    my $with_increase = defined($increase) ? " (+" . commify($increase) . ")" : "";
    return $label . " ". commify($cumulative_sum) . $with_increase;
}

sub dose_bar($cumulative_sum) {
    my $o = build_progress_bar($cumulative_sum, POPULATION_OF_TAIWAN);
    return $o->{"bar"} . " " . $o->{"percentage"} . "\%";
}

sub build_progress_bar($n, $base) {
    my $percentage = 100 * $n / $base;
    my $width = 10;
    my $p = int $width * $percentage / 100;
    my $q = $width - $p;
    my $bar = ("█" x $p) . ("▁" x $q);
    $percentage = int(100 * $percentage) / 100;
    return { "bar" => $bar, "percentage" => $percentage };
}

sub full_progress ($opts) {
    my $body;
    if ($opts->{"csv-file"}) {
        $body = Mojo::File->new($opts->{"csv-file"})->slurp;
    } else {
        my $url = $opts->{"csv-url"} // "https://raw.githubusercontent.com/owid/covid-19-data/master/public/data/vaccinations/country_data/Taiwan.csv";
        my $res = Mojo::UserAgent->new->get($url)->result;
        $res->is_success or die "Failed to fetch: $url";
        $body = $res->body;
    }

    die "No CSV" unless $body;
    return csv( "in" => \$body, "headers" => "auto");
}

sub maybe_post_update ($opts, $msg) {
    unless ($msg) {
        say "# Message is empty.";
        return;
    }

    say "# Message (length=" . length($msg) . ")";
    say "-------8<---------";
    say encode_utf8($msg);
    say "------->8---------";

    maybe_tweet_update($opts, $msg);
    maybe_toot_update($opts, $msg);
}

sub maybe_tweet_update ($opts, $msg) {
    my $config;

    if ($opts->{"twitter-config"} && -f $opts->{"twitter-config"}) {
        say "[INFO] Loading config from " . $opts->{"twitter-config"};
        $config = YAML::LoadFile( $opts->{"twitter-config"} );
    } else {
        say "[INFO] No Twitter config.";
    }

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

sub maybe_toot_update ($opts, $msg) {
    my $config;

    if ($opts->{'mastodon-config'} && -f $opts->{'mastodon-config'}) {
        say "[INFO] Loading config from " . $opts->{'mastodon-config'};
        $config = YAML::LoadFile( $opts->{'mastodon-config'} );
    } else {
        say "[INFO] No Mastodon config.";
    }

    if ($opts->{y} && $config) {
        say "#=> Toot for real";
        my $mastodon = Mastodon::Client->new(
            "instance"        => $config->{"instance"},
            "name"            => $config->{"name"},
            "client_id"       => $config->{"client_id"},
            "client_secret"   => $config->{"client_secret"},
            "access_token"    => $config->{"access_token"},
            "coerce_entities" => 1,
        );

        my $r = $mastodon->post_status($msg);
        say $r->url;
    } else {
        say "#=> Not tooting";
    }
}
