#!/usr/bin/perl
# Orphaned Pages for Oddmuse Wikis
# Copyright (C) 2004	Alex Schroeder <alex@emacswiki.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use CGI qw/:standard/;
use CGI::Carp qw(fatalsToBrowser);
use LWP::UserAgent;

if (not param('url')) {
  print header(),
    start_html('Orphaned Pages'),
    h1('Orphaned Pages'),
    p('$Id: orphaned.pl,v 1.2 2004/03/21 00:33:41 as Exp $'),
    p('Returns a list of orphaned pages based on a dot-file.'),
    start_form(-method=>'GET'),
    p('URL for dot-file: ', textfield('url'), br(),
      'Example: http://www.emacswiki.org/cgi-bin/alex?action=links;raw=1'),
    p('URL for list of nodes: ', textfield('nodes'), br(),
      'Example: http://www.emacswiki.org/cgi-bin/alex?action=index;raw=1'),
    p(submit()),
    end_form(),
    end_html();
  exit;
}

print header(-type=>'text/plain; charset=UTF-8');
$ua = LWP::UserAgent->new;
$request = HTTP::Request->new('GET', param('url'));
$response = $ua->request($request);
$data = $response->content;

while ($data =~ m/"(.*?)" -> "(.*?)"/g) {
  $page{$1} = 1;
  $link{$2} = 1;
}

$request = HTTP::Request->new('GET', param('nodes'));
$response = $ua->request($request);
$data = $response->content;

foreach $pg (split(/\n/, $data)) {
  $pg =~ s/_/ /g;
  $page{$pg} = 1 if $pg;
}

foreach $pg (sort keys %page) {
  print $pg, "\n" unless $link{$pg};
}
