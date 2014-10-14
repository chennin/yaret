#!/usr/bin/env perl
use strict;
use warnings;
use JSON::XS;
use LWP::UserAgent;
use POSIX qw/floor strftime/;
use DateTime;
use CGI "meta";
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);

my $json = JSON::XS->new();
my @euids = qw/2702 2714 2711 2721 2741 2722/;
my @usids = qw/1704 1707 1702 1721 1701 1706/;
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
    1701 => "Seastone",
    1706 => "Wolfsbane",
    );

my $ua = LWP::UserAgent->new(
    agent => 'Opera/9.80 (X11; Linux x86_64) Presto/2.12.388 Version/12.16',
    timeout => 30,
    );

my $usurl = "http://chat-us.riftgame.com:8080/chatservice/zoneevent/list?shardId=";
my $euurl = "http://chat-eu.riftgame.com:8080/chatservice/zoneevent/list?shardId=";

my $html = new CGI;#::Compress::Gzip;
#print $html->header; # HTTP header

print $html->start_html(
    -title => "YARET",
#    -script => { -type =>'JAVASCRIPT', -src => "sorttable.js", },
    -style => { -src => 'k.css'},
#    -onLoad => 'javascript:var myTH = document.getElementsByTagName("th")[0]; sorttable.innerSortFunction.apply(myTH, []);', # browser sort by name after load - cheat
    -head => meta({-http_equiv => 'Refresh',
                -content => '60'}),
    );

print "<center><h3>Yet Another Rift Event Tracker</h3>";
print "<div>This one with more colors</div></center>\n";

my @headers = ("Shard", "Event Name", "Zone", "Elapsed Time");
print "<table>";

print '<caption align="bottom">';
print '<span class="relevant">Max level content</span> / <span class="oldnews">Old content</span> + <span class="new">Event just starting</span>';
my $dt =  DateTime->now(time_zone => 'America/Los_Angeles');
print '<div><small>Generated ' . $dt->strftime("%F %T %Z") . '</small></div>';
print '</caption>';
print "<thead><tr>\n";
foreach my $header (@headers) {
  print "<th>$header</th>";
}

print "</tr></thead>\n";

foreach my $zoneid (@usids) {
  print "<tbody>\n";
  my $site = $ua->get("$usurl$zoneid");
  my $result = $json->decode($site->content);
  print "<tr><td class='label'>$usnames{$zoneid}</td><td></td><td></td><td></td></tr>";
  my @text = ("", "");
  foreach my $zone (@{ $result->{"data"} }) {
    if ($zone->{"name"}) { 
      my $time = floor((time - $zone->{"started"})/60);

      my $class = "oldnews"; my $place = 1;
      if ($zone->{"zone"} =~ /^(The Dendrome|Steppes of Infinity|Morban|Ashora|Kingsward)$/) { $class = "relevant"; $place = 0; }

      if ($zone->{"name"} eq "Hooves and Horns") { $class .= " pony"; }
#      if ($zone->{"name"} eq "The Awakening") { $class .= " pony"; }

      if ($time < 4) { $class .= " new"; }

      $text[$place] .= "<tr class='$class'>\n";
      $text[$place] .= "<td></td>";
      $text[$place] .= "<td>" . $zone->{"zone"} . "</td>";
      $text[$place] .= "<td>" . $zone->{"name"} . "</td>";
      $text[$place] .= "<td>" . $time . "m</td>"; 
      $text[$place] .= "</tr>\n";
    }
  }
  print $text[0];
  print $text[1];
  print "</tbody>\n";
}

print "</table>\n";
print $html->end_html;
