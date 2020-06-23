#!/usr/bin/env perl
#The MIT License (MIT)
#  Copyright (c) 2017 Christopher Henning
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
use XML::RSS;
use Date::Parse;
use POSIX qw/floor strftime/;
use DateTime;
use CGI qw/meta param/;
use File::Temp qw/tempfile/;
use Config::Simple;
use DBD::mysql;
use Time::HiRes qw/gettimeofday tv_interval/;
use File::Copy;
use File::Basename;
use Cwd qw/abs_path/;

my $t0 = [gettimeofday];

my $REFRESH = 60;
my $TIMEOUT = 4; # Timeout per HTTP request to the Rift server (one per shard)
my $CONFIGFILE = dirname(abs_path(__FILE__)) . "/ret.conf";

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
foreach my $lang (@langs) {
  if (!$mapsbyid{$lang}) { $mapsbyid{$lang} = (); }
  $sth = $dbh->prepare("SELECT id,map FROM maps WHERE lang = ?");
  $sth->execute($lang) or die "Can't get maps. $DBI::errstr\n"; 
  while (my $row = $sth->fetchrow_hashref()) {
    $mapsbyid{$lang}{$row->{'id'}} = $row->{'map'};
  }
}
$maps = keys %{ $mapsbyid{"en_US"} };

# Get & store shards to reference by name and ID
my (%eubyid, %nabyid, %eubyname, %nabyname, %primebyname, %primebyid, %pvps);
$sth = $dbh->prepare("SELECT id, name, dc, pvp FROM shards WHERE active = true");
my $success = $sth->execute();
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
    elsif ($row->{'dc'} eq "prime") {
      $primebyid{$row->{'id'}} = $row->{'name'};
      $primebyname{$row->{'name'}} = $row->{'id'};
    }
# Keep track of PvP servers for later in/exclusion from average times
    $pvps{$row->{'name'}} = $row->{'pvp'};
  }
}

# Get & store zone definitions                                                                                                                                                                       
my %zonesbyid = ();
my %zonelevel = ();
foreach my $lang (@langs) {
    if (!$zonesbyid{$lang}) { $zonesbyid{$lang} = (); }
    $sth = $dbh->prepare("SELECT id, name, maxlevel FROM zones WHERE lang=?");
    $sth->execute($lang) or die "Can't get zone names. $DBI::errstr\n";
    while (my $row = $sth->fetchrow_hashref()) {                                                                                                                                                       
      $zonesbyid{$lang}{$row->{'id'}} = $row->{'name'};
      $zonelevel{$row->{'id'}} = $row->{'maxlevel'};
    }
}

my %nadc = (
    url => "https://web-api-us.riftgame.com/chatservice/zoneevent/list?shardId=",
    shortname => "na",
    shardsbyid => \%nabyid,
    shardsbyname => \%nabyname,
    tz => "America/Los_Angeles",
    );
my %eudc = (
    url => "https://web-api-eu.riftgame.com/chatservice/zoneevent/list?shardId=",
    shortname => "eu",
    shardsbyid => \%eubyid,
    shardsbyname => \%eubyname,
    tz => "GMT",
    );
my %primedc = (
    url => "https://web-api-us.riftgame.com/chatservice/zoneevent/list?shardId=",
    shortname => "prime",
    shardsbyid => \%primebyid,
    shardsbyname => \%primebyname,
    tz => "America/Los_Angeles",
    );

my @dcs = ();
push(@dcs, \%nadc);
push(@dcs, \%eudc);
#push(@dcs, \%primedc);

# Make sure output folders are correct
sub createdir($) {
   my $dir = shift;
   if (-e $dir) {
      if (!-d $dir) { die "$dir exists but is not a directory. $!\n"; }
      return;
   }
   if (!mkdir $dir) { die "Unable to create $dir. $!\n"; }
   if (chmod(0755, $dir) != 1) { print STDERR "Unable to set permissions on $dir, you may not be able to access it.\n" }
}
sub createlink($$) {
  my $target = shift;
  my $linkname = shift;
  if (!-e $linkname) { symlink($target, $linkname); }
}
if ($WWWFOLDER !~ m@/$@) { $WWWFOLDER .= '/'; }
createdir($WWWFOLDER);
foreach my $dc (@dcs) {
  createdir($WWWFOLDER . $dc->{"shortname"});
  createlink($WWWFOLDER . $dc->{"shortname"} . "/en_US.html", $WWWFOLDER . $dc->{"shortname"} . "/index.html");
}
my $srcdir = dirname(abs_path(__FILE__)) . "/";
createlink($srcdir . "toplevelindex.html", $WWWFOLDER . "index.html");
createlink($srcdir . "yaret.js", $WWWFOLDER . "yaret.js");
createlink($srcdir . "ret.css", $WWWFOLDER . "ret.css");
foreach my $lang (@langs) {
  createlink($srcdir . $lang . ".png", $WWWFOLDER . $lang . ".png");
}

# REALLY DO NOT EDIT BELOW THIS LINE

# Set up "browser"
my $ua = LWP::UserAgent->new(
    timeout => $TIMEOUT,
    );

my $json = JSON::XS->new();

# Get last known state of running events from SQL
my $laststate = ();
$sth = $dbh->prepare("SELECT * FROM events WHERE endtime = 0");
$sth->execute() or die "Can't get running events. $DBI::errstr\n";
$laststate = $sth->fetchall_arrayref({});

# Go through each DC, retrieve events, and insert new events
foreach my $dc (@dcs) {
  foreach my $shardname (sort keys %{ $dc->{"shardsbyname"} } ) {  # %{ ... } = turning an array reference into a usable array
    my $site = $ua->get($dc->{"url"} . $dc->{'shardsbyname'}{$shardname});
    if (!$site->is_success) {
#      if (($site->status_line ne "500 Status read failed: Connection reset by peer") && ($site->status_line ne "500 read timeout")) {
              print STDERR "Error retrieving events for " .  $shardname . ". " . $site->status_line . "\n";
#      }
      next;
    }
    my $result = undef;
    eval { $result = $json->decode($site->decoded_content()) or die "Can't decode JSON result. $!\n-----\n$site->decoded_content()\n-----"; };
    if ($@) { die "Can't decode JSON result. " . $! . "\n" . $site->decoded_content() . "\n"; }
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
            unless (($eventsbyname{$zone->{'name'}} == 202) && ($zone->{'started'} + 7200 < time)) { my $removed = splice(@{ $laststate }, $index, 1); }
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
}

# Any rows still in the last known state table are not currently running so the
# end time should be updated.
foreach my $row (@{ $laststate }) {
#  if (($row->{'eventid'} == 202) && ($row->{'starttime'} + 7200 > time)) { next; }
  $sth = $dbh->prepare("UPDATE events SET endtime = ? WHERE shardid = ? AND zoneid = ? AND eventid = ? AND starttime = ? AND endtime = 0");
  my $endtime = time;
  my $maxtime = findmaxtime($row->{'eventid'});
# If the end time is more than the max (due to server restarts and API keeping
# them up) set it to the max + 1 minute
  if ($endtime - $row->{'starttime'} > $maxtime) { $endtime = $row->{'starttime'} + $maxtime + 60; }
  my $success = $sth->execute($endtime, $row->{'shardid'}, $row->{'zoneid'}, $row->{'eventid'}, $row->{'starttime'});
  if (!$success) {
    print STDERR "Error removing. " . $DBI::errstr . "\n";
    print STDERR time . "$row->{'shardid'}, $row->{'zoneid'}, $row->{'eventid'}, $row->{'starttime'}\n";
  }
}

# Time start to SQL populated
my $elapsed1 = tv_interval($t0);

my %maint;
my $rss = new XML::RSS;
foreach my $dc (@dcs) {
  $maint{$dc->{"shortname"}} = "";
  my $mdc = $dc->{"shortname"};
  if ($mdc eq "prime") {
    $mdc = "na";
    if (defined($maint{$mdc})) { $maint{$dc->{"shortname"}} = $maint{$mdc}; next; }
  }
  my $site = $ua->get("http://rss.trionworlds.com/live/maintenance/rift-${mdc}-en.rss");
  if ($site->is_success) {
    $rss->parse($site->decoded_content);
    foreach my $item (@{$rss->{'items'}}) {
      $item->{'pubDate'} =~ s/PST/PDT/; #hack
      $item->{'pubDate'} =~ s/CST/CDT/; #hack
      #my $mainttime = DateTime->from_epoch(epoch => str2time($item->{'pubDate'}, time_zone => "-0600"))->epoch();
      #print DateTime->now()->epoch . " " . str2time($item->{'pubDate'}, "America/Chicago") . " " . $mainttime . "\n";
      if (DateTime->now()->epoch > str2time($item->{'pubDate'})) { $maint{$dc->{"shortname"}} = $item->{'link'}; }
    }
  }
}

# Now construct web page with only current events
foreach my $dc (@dcs) {
  my $t1 = [gettimeofday];
  my $html = new CGI;
# Safely use temp files (moved later)
  my %outfiles = ();
  foreach my $lang (@langs) {
    my ($temp, $filename) = tempfile("ret_${lang}_XXXXX", TMPDIR => 1, UNLINK => 0);
    binmode($temp, ':utf8');
    $outfiles{$lang} = $temp;
    $outfiles{"${lang}name"} = $filename;

    my $start = $html->start_html(
        -title => "YARET",
        -encoding => 'UTF-8',
        -style => { -src => '../ret.css'},
        -head => meta({
          -http_equiv => 'Refresh',
          -content => "$REFRESH"
          }),
        -script => [
          { -type =>'JAVASCRIPT', -src => "../sorttable.js", },
          { -type =>'JAVASCRIPT', -src => "../yaret.js", },
#          { -type =>'JAVASCRIPT', -src => "http://www.magelocdn.com/pack/rift/en/magelo-bar.js#1", },
          ],
        );
    # Hack for HTML 5 DTD.  Move off of CGI?
    my $dtd = '<!DOCTYPE html>';
    $start =~  s{<!DOCTYPE.*?>}{$dtd}s;
    print $temp $start;
    print $temp "<h2 class=\"normal\">Yet Another Rift Event Tracker</h2>";

# Insert links to other languages
    print $temp "<p class=\"normal\">Language: ";
    foreach my $otherlang (@langs) {
      if ($lang ne $otherlang) { print $temp '<a href="' . $otherlang . '.html"><img src="../' . $otherlang . '.png" alt="' . $otherlang . ' flag" /></a> '; }
      else { print $temp "<img class=\"gray\" src=\"../$otherlang.png\" alt=\"$otherlang flag\" /> "; }
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
#    if ($dc->{"shortname"} eq "na") {
#      print $temp '<h3 style="color:skyblue;" class="normal">News Message</h2>';
#   }
    if ($maint{$dc->{"shortname"}} ne "") {
      print $temp '<h4 class="normal" style="color:lemonchiffon;" class="normal"><em>NOTE</em>: RIFT is currently in a <a href="' . $maint{$dc->{"shortname"}} . '">planned maintenance window</a> so anything below may be inaccurate.</h4>';
    }

# Construct table
    print $temp '<div class="caption" id="caption">' . "\n";
    print $temp '<h3>About</h3>';
    print $temp 'This site shows you all currently running zone events in <a href="http://www.trionworlds.com/rift/en/">RIFT</a>. Select your region and language, check the list, get in game and go there!';
    print $temp '<hr /><h4>Event Formatting</h4><div class="new">Recently started</div> <div class="nearavg">Nearing/over its average run time</div> <div class="nearend">Nearing its maximum run time</div>';
    print $temp '<br /><div class="unstable">Unstable Artifact</div> <div class="yule">Seasonal / Special event</div> <div class="vostigar">Vostigar Peaks event</div>';
    print $temp '<br /><div class="pvp1">PvP server <a onclick="showHidePvP();" id="pvptoggle">(hide)</a></div>';
    print $temp '<hr /><h4>Usage</h4><div>Find an event you are interested in. Hop to the shard it is on and teleport there, then do the event! But remember that an event may complete (or fail) before you get there!</div>';
    print $temp '<br /><div>Click an event to <span class="tagged">gray</span> it out.</div>';
    print $temp '<br /><div>Hover over the elapsed time to see the average run time of this event over the last 30 days in this region.</div>';
    print $temp '<br /><div>Click a map name to hide the entire map.</div>';
    print $temp '<hr /><div>This page refreshes once a minute.</div>' . "\n";
    print $temp '</div>' . "\n";
    print $temp '<div class="caption"><a onclick="showHideLegend();" id="legendtoggle">Click to hide this About sidebar</a></div>' . "\n";
  }
  my @headers = ("Event", "Shard", "Zone", "Age");

# Retrieve events
  for (my $map = $maps; $map > 0; $map--) {
    if ($map > 1 && $dc->{"shortname"} eq "prime") { next; } # Prime short-circuit
    $sth = $dbh->prepare("SELECT * FROM events WHERE endtime = 0 AND shardid IN (SELECT id FROM shards WHERE dc = ?) AND zoneid IN (SELECT id FROM zones WHERE mapid = ?) ORDER BY starttime ASC");
    my $success = $sth->execute($dc->{"shortname"}, $map) or die "Unable to retrieve events for map. $!";
    if ($sth->rows == 0) {
      foreach my $lang (@langs) {
        print { $outfiles{$lang} } "<h4 class=\"label\" title=\"Zero events found\">&empty; $mapsbyid{$lang}{$map} </h4>\n";
      }
      next;
    }
    foreach my $lang (@langs) {
      my $temp = $outfiles{$lang};
      print $temp "<h4 class=\"label downarrow\" onclick=\"showHide('$map')\" id=\"label$map\">$mapsbyid{$lang}{$map} </h4>\n";
      print $temp "<table class='ret sortable' id=\"table$map\">";
      print $temp "<thead>\n<tr class=\"header\">";
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
      my $planes = undef;
      if ($map == $maps) { $class = "relevant"; }
      if ($row->{"eventid"} == 158) { $class .= " pony"; } # Hooves and Horns
#      elsif ($row->{"eventid"} == 154) { $class .= " behemoth"; }
      elsif (($row->{"eventid"} == 129) || (($row->{"eventid"} >= 187) && ($row->{"eventid"} <= 192))) { $class .= " yule"; }
      elsif (($row->{"eventid"} >= 130) && ($row->{"eventid"} <= 153) && ($row->{"eventid"} != 152)) { $class .= " unstable"; }
#      elsif (($row->{"eventid"} >= 201) && ($row->{"eventid"} <= 202)) { $class .= " fortress"; }
      elsif (($row->{"eventid"} >= 206) && ($row->{"eventid"} <= 211)) { $class .= " vostigar"; }

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
# Hide events past their max run times due to API after restarts
# Fudge by 1 minute under max time (if we're displaying the max time for an event, it's over)
      if ($time > ($maxtime/60 - 1)) { next; }

      my $sthp = $dbh->prepare("SELECT planes FROM eventnames WHERE id=? LIMIT 1");
      $sthp->execute($row->{"eventid"}) or die $!;
      ($planes) = $sthp->fetchrow_array;
      #print STDERR $planes;
# Fill in events
      foreach my $lang (@langs) {                                                                                                                                                                      
        my $temp = $outfiles{$lang};
        my $id = "$row->{'eventid'}_$row->{'shardid'}_$row->{'zoneid'}_$row->{'starttime'}";
        print $temp "<tr class='$class' id='$id'>";
#        print STDERR "$row->{'eventid'}\n";
        print $temp "<td class='$class'>" . $eventsbyid{$lang}{$row->{"eventid"}};
        if (defined($planes) && $planes ne "") {
		foreach my $plane (split(",",$planes)) {
			print $temp ' <img alt="(' . $plane . ')" src="../icon/' . $plane . '.png" />';
		}
	}
        print $temp "</td>";
        print $temp "<td class='$class pvp$pvp'>" . $dc->{'shardsbyid'}{$row->{"shardid"}} . "</td>";
        print $temp "<td sorttable_customkey=\"" . (100 - $zonelevel{$row->{"zoneid"}}) . "\" class='$class'>" . $zonesbyid{$lang}{$row->{"zoneid"}} . "</td>";
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
# Web site constructed
    my $elapsed2 = tv_interval ($t1);

    my $dt = DateTime->now(time_zone => $dc->{"tz"});
    print $temp '<p></p><p class="disclaimer">Generated ' . $dt->strftime("%F %T %Z") . ' in ' . $elapsed1 . 's + ' . $elapsed2 . 's</p>';

    print $temp "<p class=\"disclaimer\">Supported browsers: Chrome 62+, Edge 16+, Firefox 52+, Safari 11+</p>";
    print $temp "<p class=\"disclaimer\">Trion, Trion Worlds, RIFT, Storm Legion, Nightmare Tide, Prophecy of Ahnket, Telara, and their respective logos, are trademarks or registered trademarks of Trion Worlds, Inc. in the U.S. and other countries. This site is not affiliated with Trion Worlds or any of its affiliates.</p>\n";
    print $temp "<p class=\"disclaimer\">This site uses cookies and local storage to store user preferences. <a onclick=\"eraseCookie('sort'); eraseCookie('map1'); eraseCookie('map2'); eraseCookie('map3'); eraseCookie('pvp'); eraseCookie('hideLegend'); clearLocalStorage()\">Erase cookies and local storage</a>.</p>\n";
    print $temp "<p class=\"disclaimer\">Contact via the <a href=\"http://forums.riftgame.com/private.php?do=newpm&u=6789104\">RIFT forums</a>.</p>\n";
    print $temp $html->end_html;
    close $temp;

    chmod oct("0644"), $tempname;
    move($tempname, $WWWFOLDER . $dc->{"shortname"} . '/' . $lang . ".html") or die "Unable to move file. $!";
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
