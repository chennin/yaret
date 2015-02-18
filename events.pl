#!/usr/bin/env perl
#The MIT License (MIT)
#  Copyright (c) 2015 Christopher Henning
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

use strict;
use warnings;
use JSON::XS;
use LWP::UserAgent;
use POSIX qw/floor strftime/;
use DateTime;
use CGI qw/meta param/;
use File::Temp qw/tempfile/;
use Config::Simple;
use DBD::mysql;
use Time::HiRes qw/gettimeofday tv_interval/;
use File::Copy;
use encoding qw/utf8/;

my $t0 = [gettimeofday];

my $REFRESH = 60;
my $TIMEOUT = 5; # Timeout per HTTP request to the Rift server (one per shard)
my $CONFIGFILE = "/home/alucard/rift/ret.conf";

# DO NOT EDIT BELOW THIS LINE
sub findmaxtime($);

my $cfg = new Config::Simple($CONFIGFILE) or die "Failed to read config. $!\n";
my ($dsn, $dbh, $sth);

my $WWWFOLDER = "/var/www/rift/"; # include trailing slash
if (defined $cfg->param('WWWFOLDER')) { $WWWFOLDER = $cfg->param('WWWFOLDER'); }

# Set up SQL connection
if ((defined $cfg->param('SQLDB')) && (defined $cfg->param('SQLLOC')) && (defined $cfg->param('SQLUSER')) && (defined $cfg->param('SQLPASS'))) {
  $dsn = "DBI:mysql:database=" . $cfg->param('SQLDB') . ";host=" . $cfg->param('SQLLOC') . ";";
  $dbh = DBI->connect($dsn, $cfg->param('SQLUSER'), $cfg->param('SQLPASS'), { mysql_enable_utf8 => 1, });
  if (!defined $dbh) {
    print STDERR "Error connecting to databse. " . $DBI::errstr . "\n";
  }
}
else { die "Insufficient SQL settings!\n"; }

# Get & store event definitions
my %eventsbyname;
$sth = $dbh->prepare("SELECT id, name FROM eventnames");
$sth->execute() or die "Can't get event names. $DBI::errstr\n";
while (my $row = $sth->fetchrow_hashref()) {
  $eventsbyname{$row->{'name'}} = $row->{'id'};
}

# Find languages
$sth = $dbh->prepare("SELECT DISTINCT lang FROM eventnames ORDER BY lang LIMIT 5");
$sth->execute() or die "Can't find languages. $DBI::errstr\n";
my @langs;
while (my $row = $sth->fetchrow_hashref()) {
  push(@langs, $row->{'lang'});
}

# Fill events by ID based on user language
my %eventsbyid = ();
foreach my $lang (@langs) {
  if (!$eventsbyid{$lang}) { $eventsbyid{$lang} = (); }
  $sth = $dbh->prepare("SELECT id, name FROM eventnames WHERE lang=?");
  $sth->execute($lang) or die "Can't get event names for $lang. $DBI::errstr\n";
  while (my $row = $sth->fetchrow_hashref()) {
    $eventsbyid{$lang}{$row->{"id"}} = $row->{"name"};
  }
}

# Get & store maps
my $maps = 0;
my %mapsbyid = ();
$sth = $dbh->prepare("SELECT id,map FROM maps");
my $success = $sth->execute();
if (!$success) { die "Can't get maps. $DBI::errstr\n"; }
else {
  while (my $row = $sth->fetchrow_hashref()) {
    if (!$mapsbyid{$row->{'id'}}) { $mapsbyid{$row->{'id'}} = $row->{'map'}; }
  }
}
$maps = keys %mapsbyid;

# Get & store shards to reference by name and ID
my (%eubyid, %nabyid, %eubyname, %nabyname, %pvps);
$sth = $dbh->prepare("SELECT id, name, dc, pvp FROM shards");
$success = $sth->execute();
if (!$success) { die "Can't get shards. $DBI::errstr\n"; }
else {
  while (my $row = $sth->fetchrow_hashref()) {
    if ($row->{'dc'} eq "eu") {
      $eubyid{$row->{'id'}} = $row->{'name'};
      $eubyname{$row->{'name'}} = $row->{'id'};
    }
    elsif ($row->{'dc'} eq "na") {
      $nabyid{$row->{'id'}} = $row->{'name'};
      $nabyname{$row->{'name'}} = $row->{'id'};
    }
# Keep track of PvP servers for later in/exclusion from average times
    $pvps{$row->{'name'}} = $row->{'pvp'};
  }
}

# Get & store zone definitions                                                                                                                                                                       
my %zonesbyid = ();
foreach my $lang (@langs) {
    if (!$zonesbyid{$lang}) { $zonesbyid{$lang} = (); }
    $sth = $dbh->prepare("SELECT id, name FROM zones WHERE lang=?");
    $sth->execute($lang) or die "Can't get zone names. $DBI::errstr\n";
    while (my $row = $sth->fetchrow_hashref()) {                                                                                                                                                       
      $zonesbyid{$lang}{$row->{'id'}} = $row->{'name'};
    }
}

my %nadc = (
    url => "http://chat-us.riftgame.com:8080/chatservice/zoneevent/list?shardId=",
    shortname => "na",
    shardsbyid => \%nabyid,
    shardsbyname => \%nabyname,
    tz => "America/Los_Angeles",
    );
my %eudc = (
    url => "http://chat-eu.riftgame.com:8080/chatservice/zoneevent/list?shardId=",
    shortname => "eu",
    shardsbyid => \%eubyid,
    shardsbyname => \%eubyname,
    tz => "GMT",
    );

my @dcs = ();
push(@dcs, \%nadc);
push(@dcs, \%eudc);

# REALLY DO NOT EDIT BELOW THIS LINE

# Set up "browser"
my $ua = LWP::UserAgent->new(
    agent => 'Opera/9.80 (X11; Linux x86_64) Presto/2.12.388 Version/12.16',
    timeout => $TIMEOUT,
    );

my $json = JSON::XS->new();

# Get last known state of running events from SQL
my $laststate = ();
$sth = $dbh->prepare("SELECT * FROM events WHERE endtime = 0");
$sth->execute() or die "Can't get running events. $DBI::errstr\n";
$laststate = $sth->fetchall_arrayref({});

# Go through each DC, retrieve events, and construct web pages
foreach my $dc (@dcs) {
  foreach my $shardname (sort keys %{ $dc->{"shardsbyname"} } ) {  # %{ ... } = turning an array reference into a usable array
    my $site = $ua->get($dc->{"url"} . $dc->{'shardsbyname'}{$shardname});
    if (!$site->is_success) {
      print STDERR "Error retrieving events for " .  $shardname . ". " . $site->status_line . "\n";
      next;
    }
    my $result = $json->decode($site->content) or die "Can't decode JSON result. $!\n";
    foreach my $zone (@{ $result->{"data"} }) { 
      if ($zone->{"name"}) { # an event
        if ($zone->{"name"} eq "Terror aus der Tiefe") { $zone->{"name"} = "Terror aus den Tiefen"; } # Fix for inconsistent Trion translation
# Compare current event state with last known state
# * Add new events into SQL
# * Remove still-running events from last known state for later marking events as
# finished
        my $seenagain = 0;
        for (my $index = $#{ $laststate }; $index >= 0; --$index) {
          my $row = $laststate->[$index];
          if ($row->{'shardid'} eq $dc->{'shardsbyname'}{$shardname} && $row->{'zoneid'} eq $zone->{'zoneId'} && $row->{'eventid'} eq $eventsbyname{$zone->{'name'}} && $row->{'starttime'} eq $zone->{'started'}) {
            $seenagain = 1;
            my $removed = splice(@{ $laststate }, $index, 1);
          }
        }

        if ($seenagain == 0) { # new event
          $sth = $dbh->prepare("INSERT INTO events (shardid, zoneid, eventid, starttime) VALUES (?, ?, ?, ?)");
          my $success = $sth->execute($dc->{'shardsbyname'}{$shardname}, $zone->{'zoneId'}, $eventsbyname{$zone->{'name'}}, $zone->{'started'});
          if (!$success) {
            if ($dbh->err == 1062) { # MySQL 'Duplicate entry for key PRIMARY' - event erroneously removed before end
              $sth = $dbh->prepare("UPDATE events SET endtime = 0 WHERE shardid = ? AND zoneid = ? AND eventid = ? AND starttime = ?");
              $success = $sth->execute($dc->{'shardsbyname'}{$shardname}, $zone->{'zoneId'}, $eventsbyname{$zone->{'name'}}, $zone->{'started'});
            }
          }
          if (!$success) {
            print STDERR "Error updating. " . $dbh->err . ": " . $DBI::errstr . "\n";
            print STDERR "Params: $dc->{'shardsbyname'}{$shardname}//$shardname, $zone->{'zoneId'}==$zone->{'zone'}, $eventsbyname{$zone->{'name'}}==$zone->{'name'}, $zone->{'started'}//$zone->{'started'}\n";
          }
        } # new event
      } # an event
    }
  }
# Now construct page
  my $html = new CGI;
# Safely use temp files (moved later)
  my %outfiles = ();
  foreach my $lang (@langs) {
    my ($temp, $filename) = tempfile("ret_${lang}_XXXXX", TMPDIR => 1, UNLINK => 0);
    binmode($temp, ':utf8');
    $outfiles{$lang} = $temp;
    $outfiles{"${lang}name"} = $filename;

    print $temp $html->start_html(
        -title => "YARET",
        -encoding => 'UTF-8',
        -style => { -src => '../ret.css'},
        -head => meta({
          -http_equiv => 'Refresh',
          -content => "$REFRESH"
          }),
        -script => [
          { -type =>'JAVASCRIPT', -src => "../sorttable.js", },
          { -type =>'JAVASCRIPT', -src => "../yaret.js", }
          ],
        );
    print $temp "<h2 class=\"normal\">Yet Another Rift Event Tracker</h2>";

# Insert links to other languages
    print $temp "<p class=\"normal\">Language: ";
    foreach my $otherlang (@langs) {
      if ($lang ne $otherlang) { print $temp '<a href="' . $otherlang . '.html"><img src="../' . $otherlang . '.png"></a> '; }
      else { print $temp "<img class=\"gray\" src=\"../$otherlang.png\"> "; }
    }

# Insert links to other datacenter's pages
    print $temp " Datacenter:\n";
    foreach my $otherdc (@dcs) {
      if ($dc != $otherdc) {
        print $temp '<a href="../'. $otherdc->{"shortname"} . '/' . $lang . '.html">' . uc($otherdc->{"shortname"}) . "</a> ";
      }
      else { print $temp uc($dc->{"shortname"}) . " "; }
    }
    print $temp "</p>\n";

# Construct table
    print $temp '<span class="caption">' . "\n";
    print $temp '<br /><div class="new">Newly started event</div> <div class="nearavg">Nearing/over its average run time</div> <div class="nearend">Nearing its maximum run time</div>';
    print $temp '<br /><div class="behemoth">Bloodfire Behemoth</div> <div class="unstable">Unstable Artifact</div> <div class="pony">Unicorns</div> <div class="yule">Fae Yule</div>';
    print $temp '<br /><div class="pvp1">PvP server</div>';
    print $temp '</span>' . "\n";
  }
  my @headers = ("Event", "Shard", "Zone", "Age");

# Retrieve events
  for (my $map = $maps; $map > 0; $map--) {
    $sth = $dbh->prepare("SELECT * FROM events WHERE endtime = 0 AND shardid IN (SELECT id FROM shards WHERE dc = ?) AND zoneid IN (SELECT id FROM zones WHERE mapid = ?) ORDER BY starttime ASC");
    my $success = $sth->execute($dc->{"shortname"}, $map) or die "Unable to retrieve events for map. $!";
    foreach my $lang (@langs) {
      my $temp = $outfiles{$lang};
      print $temp "<h4 class='label'>" . $mapsbyid{$map} . "</h4>\n";
      print $temp "<table class='ret sortable'>";
      print $temp "<thead><tr>\n";
      foreach my $header (@headers) {
        print $temp "<th class='$header'>$header</th>";
      }
      print $temp "</tr>";
      print $temp "</thead>\n";
      print $temp "<tbody>\n";
    }
    while (my $row = $sth->fetchrow_hashref()) {
      my $timesecs = time - $row->{"starttime"};
      my $time = floor($timesecs/60);
      my $class = "oldnews";
      if ($map == $maps) { $class = "relevant"; }
      if ($row->{"eventid"} == 158) { $class .= " pony"; } # Hooves and Horns
      elsif ($row->{"eventid"} == 154) { $class .= " behemoth"; }
      elsif ($row->{"eventid"} == 129) { $class .= " yule"; }
      elsif (($row->{"eventid"} >= 130) && ($row->{"eventid"} <= 153) && ($row->{"eventid"} != 152)) { $class .= " unstable"; }
# Minutes to consider an event new
      if ($time < 5) { $class .= " new"; }
# Find average run time for this event on this cluster
      my $avgruntime;
      my @params = ();
      push(@params, $row->{"eventid"});
      my $shardstr = " AND (";
      my $pvp = $pvps{ $dc->{"shardsbyid"}{$row->{"shardid"}} };
      if (!defined($pvp)) { $pvp = 0; }
# Only include servers of the same PvP-ness
      foreach my $otherid (keys %{ $dc->{"shardsbyid"} }) {
        if ($pvp == $pvps{$dc->{"shardsbyid"}->{$otherid}}) {
          $shardstr .= "shardid = ? OR ";
          push(@params, $otherid);
        }
      }
      $shardstr = substr($shardstr, 0, -3); # Remove final "OR "
      $shardstr .= ")";
      my $sincetime = time - 60*60*24*30; # Last month
      my $sth2 = $dbh->prepare("SELECT FLOOR(AVG(endtime - starttime)/60) FROM events WHERE eventid = ? AND endtime >= $sincetime $shardstr");
      $sth2->execute( @params );
      ($avgruntime) = $sth2->fetchrow_array;

      my $nearend = "good";
      if ((!defined $avgruntime) || ($avgruntime !~ /^\d+$/)) { $avgruntime = "&lt;THERE IS AS YET INSUFFICIENT DATA FOR A MEANINGFUL NUMBER&gt;"; }
      elsif ($time > ($avgruntime - 6)) { $nearend = "nearavg"; }

# Find max run time for this event
      my $maxtime = findmaxtime($row->{'eventid'});
      if ($time > ($maxtime/60 - 6)) { $nearend = "nearend"; }

# Fill in events
      foreach my $lang (@langs) {                                                                                                                                                                      
        my $temp = $outfiles{$lang};
        print $temp "<tr class='$class'>\n";
        print $temp "<td>" . $eventsbyid{$lang}{$row->{"eventid"}} . "</td>";
        print $temp "<td class='pvp${pvp}'>" . $dc->{'shardsbyid'}{$row->{"shardid"}} . "</td>";
        print $temp "<td>" . $zonesbyid{$lang}{$row->{"zoneid"}} . "</td>";
        print $temp "<td sorttable_customkey=\"" . (100000 - $timesecs) . "\" class=\"$nearend\" title=\"This event ended in an average of $avgruntime minutes in the past 30 days.\">" . $time . "m</td>";
        print $temp "</tr>\n";
      }
    }
    foreach my $lang (@langs) {                                                                                                                                                                      
      my $temp = $outfiles{$lang};
      print $temp "</tbody>\n";
      print $temp "</table>\n";
    }
  }

# Construct footer
  foreach my $lang (@langs) {                                                                                                                                                                      
    my $temp = $outfiles{$lang};
    my $tempname = $outfiles{"${lang}name"};
    my $elapsed = tv_interval ($t0);

    print $temp '<p class="footer">Hover over the elapsed time to see the average run time of this event (by cluster, with/without the PvP server(s)).</p>';

    my $dt = DateTime->now(time_zone => $dc->{"tz"});
    print $temp '<p></p><p class="disclaimer">Generated ' . $dt->strftime("%F %T %Z") . ' in ' . $elapsed . 's</p>';

    print $temp "<p class=\"disclaimer\">Trion, Trion Worlds, RIFT, Storm Legion, Nightmare Tide, Telara, and their respective logos, are trademarks or registered trademarks of Trion Worlds, Inc. in the U.S. and other countries. This site is not affiliated with Trion Worlds or any of its affiliates.</p>\n";
    print $temp "<p class=\"disclaimer\">This site uses cookies to store user preferences. <a onclick=\"eraseCookie('sort')\">Erase cookies</a>.</p>\n";
    print $temp $html->end_html;
    close $temp;

    chmod oct("0644"), $tempname;
    move($tempname, $WWWFOLDER . $dc->{"shortname"} . '/' . $lang . ".html") or die "Unable to move file. $!";
  }
}
# Any rows still in the last known state table are not currently running so the
# end time should be updated.
foreach my $row (@{ $laststate }) {
  $sth = $dbh->prepare("UPDATE events SET endtime = ? WHERE shardid = ? AND zoneid = ? AND eventid = ? AND starttime = ? AND endtime = 0");
  my $endtime = time;
  my $maxtime = findmaxtime($row->{'eventid'});
# If the end time is more than the max (due to server restarts and API keeping
# them up, set it to the max + 1 minute
  if ($endtime - $row->{'starttime'} > $maxtime) { $endtime = $row->{'starttime'} + $maxtime + 60; }
  my $success = $sth->execute($endtime, $row->{'shardid'}, $row->{'zoneid'}, $row->{'eventid'}, $row->{'starttime'});
  if (!$success) {
    print STDERR "Error removing. " . $DBI::errstr . "\n";
    print STDERR time . "$row->{'shardid'}, $row->{'zoneid'}, $row->{'eventid'}, $row->{'starttime'}\n";
  }
}

sub findmaxtime($) {
# Find max run time for this event
        my $eventid = shift;
        my $maxtime = 0;
        my $sth2 = $dbh->prepare("SELECT maxruntime FROM eventnames WHERE id = ?");
        $sth2->execute($eventid) or die "Unable to get max run time for event $eventid. $!\n";
        ($maxtime) = $sth2->fetchrow_array;
        if ((!defined $maxtime) || ($maxtime !~ /^\d+$/) || ($maxtime < 0) || ($maxtime > 7200)) { $maxtime = 7200; } # absolute max is 2 hours
        return $maxtime;
}
