#!/usr/bin/env perl
use strict;
use warnings;
use JSON::XS;
use LWP::UserAgent;
use POSIX qw/floor strftime/;
use DateTime;
use CGI "meta";
use File::Temp qw/tempfile/;
use DBD::mysql;

my $REFRESH = 60;
my $WWWFOLDER = "/var/www/rift/"; # include trailing slash
my $TIMEOUT = 5; # Timeout per HTTP request to the Rift server (one per shard)

# DO NOT EDIT BELOW THIS LINE

# Set up datacenter information
# Shard IDs culled from http://chat-us.riftgame.com:8080/chatservice/shard/list
my @euids = qw/2702 2714 2711 2721 2741 2722/;
my @usids = qw/1704 1707 1702 1721 1708 1701 1706/;
my %eunames = (
    2702 => "Bloodiron",
    2714 => "Brisesol",
    2711 => "Brutwacht",
    2721 => "Gelidra",
    2741 => "Typhiria",
    2722 => "Zaviel",
    );
my %usnames = (
    1704 => "Deepwood",
    1707 => "Faeblight",
    1702 => "Greybriar",
    1721 => "Hailol",
    1708 => "Laethys",
    1701 => "Seastone",
    1706 => "Wolfsbane",
    );

my %nadc = (
    url => "http://chat-us.riftgame.com:8080/chatservice/zoneevent/list?shardId=",
    shortname => "na",
    names => \%usnames,
    ids => \@usids,
    tz => "America/Los_Angeles",
    );
my %eudc = (
    url => "http://chat-eu.riftgame.com:8080/chatservice/zoneevent/list?shardId=",
    shortname => "eu",
    names => \%eunames,
    ids => \@euids,
    tz => "GMT",
    );

my @dcs = ();
push(@dcs, \%nadc);
push(@dcs, \%eudc);

# REALLY DO NOT EDIT BELOW THIS LINE

# Set up browser.
my $ua = LWP::UserAgent->new(
    agent => 'Opera/9.80 (X11; Linux x86_64) Presto/2.12.388 Version/12.16',
    timeout => $TIMEOUT,
    );

my $json = JSON::XS->new();

# Go through each DC and construct web pages
foreach my $dc (@dcs) {
# Safely use a temp file (moved later)
  my ($temp, $filename) = tempfile("retXXXXX", TMPDIR => 1, UNLINK => 0);
  my $html = new CGI;

  print $temp $html->start_html(
      -title => "YARET",
      -encoding => 'UTF-8',
      -style => { -src => 'ret.css'},
      -head => meta({-http_equiv => 'Refresh',
        -content => "$REFRESH"}),
      );
  print $temp "<center><h3>Yet Another Rift Event Tracker</h3>";

# Insert links to other datacenter's pages
  print $temp "<p>\n";
  foreach my $otherdc (@dcs) {
    if ($dc != $otherdc) {
      print $temp '<a href="'. $otherdc->{"shortname"} . '.html">' . $otherdc->{"shortname"} . "</a> ";
    }
    else { print $temp $dc->{"shortname"} . " "; }
  }
  print $temp "</p></center>\n";

# Construct table
  my @headers = ("Shard", "Zone", "Event Name", "Elapsed Time");
  print $temp "<table>";

  print $temp "<thead><tr>\n";
  foreach my $header (@headers) {
    print $temp "<th>$header</th>";
  }

  print $temp "</tr></thead>\n";

  foreach my $zoneid ( @{ $dc->{"ids"} } ) {  # @{ ... } = turning an array reference into a usable array
    print $temp "<tbody>\n";
    my $site = $ua->get($dc->{"url"} . $zoneid);
    if (! $site->is_success) { print $temp "<tr><td class='label'>Error retrieving events for " .  $dc->{"names"}{$zoneid} . ".</td></tr></tbody>\n" ; next; }
    my $result = $json->decode($site->content) or die $!;
    print $temp "<tr><td class='label'>" .  $dc->{"names"}{$zoneid} . "</td><td></td><td></td><td></td></tr>";
# Construct zone event rows.  Max level content will be displayed first.
    my @text = ("", "");
    my $seenanold = 0;
    foreach my $zone (@{ $result->{"data"} }) {
      if ($zone->{"name"}) { 
        my $time = floor((time - $zone->{"started"})/60);

# Assign CSS classes to different events
        my $class = "oldnews"; my $place = 1;

        if ($zone->{"zone"} =~ /^(The Dendrome|Steppes of Infinity|Morban|Ashora|Kingsward|Das Dendrom|Steppen der Unendlichkeit|Königszirkel|Le Rhizome|Steppes de l'Infini|Protectorat du Roi)$/) { $class = "relevant"; $place = 0; }

        if ($zone->{"name"} =~ /^(Hooves and Horns|Des sabots et des cornes|Hufe und Hörner)$/) { $class .= " pony"; }
#      if ($zone->{"name"} eq "The Awakening") { $class .= " pony"; }
        elsif ($zone->{"name"} =~ /^(Bloodfire Behemoth|Béhémoth feu-sanglant|Blutfeuer-Ungetüm)$/) { $class .= " behemoth"; }
        elsif ($zone->{"name"} =~ /^(Dreams of Blood and Bone|Rêves de sang et d'os|Träume aus Blut und Gebeinen)$/) { $class .= " volan"; }
        elsif ($zone->{"name"} =~ /(^Unstable |^Instabil: | instables?$)/) { $class .= " unstable"; }

# Minutes to consider an event new
        if ($time < 5) { $class .= " new"; }

        if (($place == 1) && ($seenanold == 0)) { $class .= " firstold"; $seenanold = 1; }
        $text[$place] .= "<tr class='$class'>\n";
        $text[$place] .= "<td></td>";
        $text[$place] .= "<td>" . $zone->{"zone"} . "</td>";
        $text[$place] .= "<td>" . $zone->{"name"} . "</td>";
        $text[$place] .= "<td>" . $time . "m</td>"; 
        $text[$place] .= "</tr>\n";
      }
    }
    print $temp $text[0];
    print $temp $text[1];
    print $temp "</tbody>\n";
  }

  print $temp "</table>\n";

# Construct footer
  print $temp '<p align="center">Legend: </p>';
  print $temp '<p class="caption"><span class="relevant">Max level content</span>';
  print $temp '<br /><span class="oldnews olddesc">Old content</span></p>';
  print $temp '<p class="caption"><span class="new">Newly started event</span>, <span class="behemoth">Bloodfire Behemoth</span>, <span class="volan">Volan</span>, <span class="pony">Unicorns</span>, <span class="unstable">Unstable Artifact</span></p>';

  my $dt = DateTime->now(time_zone => $dc->{"tz"});
  print $temp '<p></p><p align="center"><small>Generated ' . $dt->strftime("%F %T %Z") . '</small></p>';

  print $temp "<p class=\"disclaimer\">Trion, Trion Worlds, RIFT, Storm Legion, Nightmare Tide, Telara, and their respective logos, are trademarks or registered trademarks of Trion Worlds, Inc. in the U.S. and other countries. This site is not affiliated with Trion Worlds or any of its affiliates.</p>\n"; 
  print $temp $html->end_html;

  close $temp;
  chmod oct("0644"), $filename;
  rename($filename, $WWWFOLDER . $dc->{"shortname"} . ".html");
}
