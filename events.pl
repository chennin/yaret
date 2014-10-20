#!/usr/bin/env perl
use strict;
use warnings;
use JSON::XS;
use LWP::UserAgent;
use POSIX qw/floor strftime/;
use DateTime;
use CGI "meta";
use File::Temp qw/tempfile/;
use Config::Simple;
use DBD::mysql;
use encoding qw(utf8);

my $REFRESH = 60;
my $WWWFOLDER = "/var/www/rift/"; # include trailing slash
my $TIMEOUT = 5; # Timeout per HTTP request to the Rift server (one per shard)
my $CONFIGFILE = "/home/alucard/rift/ret.conf";

# DO NOT EDIT BELOW THIS LINE
my $cfg = new Config::Simple($CONFIGFILE) or die "Failed to read config. $!\n";
my $usesql = $cfg->param('SQLENABLE');
my ($dsn, $dbh, $sth);

# Set up SQL connection
if ((defined $usesql) && (lc $usesql eq "true") && (defined $cfg->param('SQLDB')) && (defined $cfg->param('SQLLOC')) && (defined $cfg->param('SQLUSER')) && (defined $cfg->param('SQLPASS'))) {
  $dsn = "DBI:mysql:database=" . $cfg->param('SQLDB') . ";host=" . $cfg->param('SQLLOC') . ";";
  $dbh = DBI->connect($dsn, $cfg->param('SQLUSER'), $cfg->param('SQLPASS'), { mysql_enable_utf8 => 1, });
  if (!defined $dbh) {
    print STDERR "Error connecting to databse. " . $DBI::errstr . "\n";
    undef $usesql;
  }
}

# Get & store event definitions
my %eventsbyname;
if ($usesql) {
  $sth = $dbh->prepare("SELECT id, name FROM eventnames");
  $sth->execute() or die "Can't get event names. $DBI::errstr\n";

  while (my $row = $sth->fetchrow_hashref()) {
    $eventsbyname{$row->{'name'}} = $row->{'id'};
  }
}
# Get & store zone definitions
my %zonesbyname;
if ($usesql) {
  $sth = $dbh->prepare("SELECT id, name FROM zones");
  $sth->execute() or die "Can't get zone names. $DBI::errstr\n";

  while (my $row = $sth->fetchrow_hashref()) {
    $zonesbyname{$row->{'name'}} = $row->{'id'};
  }
}
# Get & store shards to reference by name and ID
my (%eubyid, %nabyid, %eubyname, %nabyname);
if ($usesql) {
  $sth = $dbh->prepare("SELECT id, name, dc FROM shards");
  $sth->execute() or die "Can't get shards. $DBI::errstr\n";

  while (my $row = $sth->fetchrow_hashref()) {
    if ($row->{'dc'} eq "eu") {
      $eubyid{$row->{'id'}} = $row->{'name'};
      $eubyname{$row->{'name'}} = $row->{'id'};
    }
    elsif ($row->{'dc'} eq "na") {
      $nabyid{$row->{'id'}} = $row->{'name'};
      $nabyname{$row->{'name'}} = $row->{'id'};
    }
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

# Set up
my $ua = LWP::UserAgent->new(
    agent => 'Opera/9.80 (X11; Linux x86_64) Presto/2.12.388 Version/12.16',
    timeout => $TIMEOUT,
    );

my $json = JSON::XS->new();

# Get last known state of events from SQL
my $laststate = ();
if ($usesql) {
  $sth = $dbh->prepare("SELECT * FROM events WHERE 'endtime' = 0");
  $sth->execute() or die $DBI::errstr;
  $laststate = $sth->fetchall_arrayref({});
}

# Go through each DC and construct web pages
foreach my $dc (@dcs) {
# Safely use a temp file (moved later)
  my ($temp, $filename) = tempfile("retXXXXX", TMPDIR => 1, UNLINK => 0);
  binmode $temp, ':utf8';
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

  foreach my $shardname (sort keys %{ $dc->{"shardsbyname"} } ) {  # @{ ... } = turning an array reference into a usable array
    print $temp "<tbody>\n";
    my $site = $ua->get($dc->{"url"} . $dc->{'shardsbyname'}{$shardname});
    if (! $site->is_success) { print $temp "<tr><td class='label'>Error retrieving events for " .  $shardname . ".</td></tr></tbody>\n" ; next; }
    my $result = $json->decode($site->content) or die $!;
    print $temp "<tr><td class='label'>" .  $shardname . "</td><td></td><td></td><td></td></tr>";
# Construct zone event rows.  Max level content will be displayed first later.
    my @text = ("", "");
    my $seenanold = 0;
    foreach my $zone (@{ $result->{"data"} }) {
      if ($zone->{"name"}) {
        my $time = floor((time - $zone->{"started"})/60);

# Assign CSS classes to different events
        my $class = "oldnews"; my $place = 1;

        if ($zone->{"zone"} =~ /^(The Dendrome|Steppes of Infinity|Morban|Ashora|Kingsward|Das Dendrom|Steppen der Unendlichkeit|Königszirkel|Le Rhizome|Steppes de l'Infini|Protectorat du Roi)$/) { $class = "relevant"; $place = 0; }

        if ($zone->{"name"} =~ /^(Hooves and Horns|Des sabots et des cornes|Hufe und Hörner)$/) { $class .= " pony"; }
        elsif ($zone->{"name"} =~ /^(Bloodfire Behemoth|Béhémoth feu-sanglant|Blutfeuer-Ungetüm)$/) { $class .= " behemoth"; }
        elsif ($zone->{"name"} =~ /^(Dreams of Blood and Bone|Rêves de sang et d'os|Träume aus Blut und Gebeinen)$/) { $class .= " volan"; }
        elsif ($zone->{"name"} =~ /(^Unstable |^Instabil: | instables?$)/) { $class .= " unstable"; }

# Minutes to consider an event new
        if ($time < 5) { $class .= " new"; }

# Find average run time for this event on this cluster
        my $avgruntime;
        if ($usesql) {
          my @params = ();
          push(@params, $eventsbyname{$zone->{'name'}});
          my $shardstr = " AND (";
          foreach my $otherid (keys %{ $dc->{"shardsbyid"} }) {
            $shardstr .= "shardid = ? OR ";
            push(@params, $otherid);
          }
          $shardstr = substr($shardstr, 0, -3); # Remove final "OR "
            $shardstr .= ")";
          $sth = $dbh->prepare("SELECT FLOOR(AVG(endtime - starttime)/60) FROM events WHERE eventid = ? AND endtime <> 0 $shardstr");
          $sth->execute( @params );
          ($avgruntime) = $sth->fetchrow_array;
        }

        my $nearend = "good";
        if ((!defined $avgruntime) || ($avgruntime !~ /^[0-9]+$/)) { $avgruntime = "<THERE IS AS YET INSUFFICIENT DATA FOR A MEANINGFUL NUMBER>"; }
        elsif ($time > ($avgruntime - 6)) { $nearend = "nearend"; }

        if (($place == 1) && ($seenanold == 0)) { $class .= " firstold"; $seenanold = 1; }
        $text[$place] .= "<tr class='$class'>\n";
        $text[$place] .= "<td></td>";
        $text[$place] .= "<td>" . $zone->{"zone"} . "</td>";
        $text[$place] .= "<td>" . $zone->{"name"} . "</td>";
        $text[$place] .= "<td class=\"$nearend\" title=\"This event lasts $avgruntime minutes on average on this cluster\">" . $time . "m</td>";
        $text[$place] .= "</tr>\n";

# Compare current event state with last known state
# * Add new events into SQL
# * Remove still-running events from last known state for later marking events as
# finished
        if ($usesql) {
          my $seenagain = 0;
          for (my $index = $#{ $laststate }; $index >= 0; --$index) {
            my $row = $laststate->[$index];
            if ($row->{'shardid'} eq $dc->{'shardsbyname'}{$shardname} && $row->{'zoneid'} eq $zonesbyname{$zone->{'zone'}} && $row->{'eventid'} eq $eventsbyname{$zone->{'name'}} && $row->{'starttime'} eq $zone->{'started'}) {
              $seenagain = 1;
              my $removed = splice(@{ $laststate }, $index, 1);
            }
          }

          if ($seenagain == 0) {
            $sth = $dbh->prepare("INSERT INTO events (shardid, zoneid, eventid, starttime) VALUES (?, ?, ?, ?)");
            my $success = $sth->execute($dc->{'shardsbyname'}{$shardname}, $zone->{'zoneId'}, $eventsbyname{$zone->{'name'}}, $zone->{'started'});
            if (!$success) {
              print STDERR "Error updating. " . $DBI::errstr . "\n";
              print STDERR "Params: $dc->{'shardsbyname'}{$shardname}//$shardname, $zone->{'zoneId'}==$zone->{'zone'}, $eventsbyname{$zone->{'name'}}==$zone->{'name'}, $zone->{'started'}//$zone->{'started'}\n";
            }
          }
        }
      }
    }

    # Max then lower level
    print $temp $text[0];
    print $temp $text[1];
    print $temp "</tbody>\n";
  }

  print $temp "</table>\n";

# Construct footer
  print $temp '<p align="center">Legend: </p>';
  print $temp '<p class="caption"><span class="relevant">Max level content</span>';
  print $temp '<br /><span class="oldnews olddesc">Old content</span></p>';
  print $temp '<p class="caption"><span class="new">Newly started event</span>, <span class="nearend">Nearing its average run time</span>, <span class="behemoth">Bloodfire Behemoth</span>, <span class="volan">Volan</span>, <span class="pony">Unicorns</span>, <span class="unstable">Unstable Artifact</span></p>';
  print $temp '<p align="center">Hover over the elapsed time to see the average run time of this event on this cluster. Run time data is since 2014-10-20.</p>';

  my $dt = DateTime->now(time_zone => $dc->{"tz"});
  print $temp '<p></p><p align="center"><small>Generated ' . $dt->strftime("%F %T %Z") . '</small></p>';

  print $temp "<p class=\"disclaimer\">Trion, Trion Worlds, RIFT, Storm Legion, Nightmare Tide, Telara, and their respective logos, are trademarks or registered trademarks of Trion Worlds, Inc. in the U.S. and other countries. This site is not affiliated with Trion Worlds or any of its affiliates.</p>\n";
  print $temp $html->end_html;

  close $temp;
  chmod oct("0644"), $filename;
  rename($filename, $WWWFOLDER . $dc->{"shortname"} . ".html");
}

# Any rows still in the last known state table are not currently running so the
# end time should be updated
if ($usesql) {
  foreach my $row (@{ $laststate }) {
    $sth = $dbh->prepare("UPDATE events SET endtime = ? WHERE shardid = ? AND zoneid = ? AND eventid = ? AND starttime = ? AND endtime = 0");
    my $success = $sth->execute(time, $row->{'shardid'}, $row->{'zoneid'}, $row->{'eventid'}, $row->{'starttime'});
    if (!$success) {
      print STDERR "Error removing. " . $DBI::errstr . "\n";
      print STDERR time . "$row->{'shardid'}, $row->{'zoneid'}, $row->{'eventid'}, $row->{'starttime'}\n";
    }
  }
}
