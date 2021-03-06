# Copyright (C) 2004  Alex Schroeder <alex@emacswiki.org>
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

use strict;
use v5.10;

AddModuleDescription('subscriberc.pl', 'Subscribed Recent Changes');

our ($bol, @MyRules, $LinkPattern, $FreeLinkPattern);

push(@MyRules, \&SubscribedRecentChangesRule);

sub SubscribedRecentChangesRule {
  if ($bol) {
    if (m/\GMy\s+subscribed\s+pages:\s*((?:(?:$LinkPattern|\[\[$FreeLinkPattern\]\]),\s*)+)categories:\s*((?:(?:$LinkPattern|\[\[$FreeLinkPattern\]\]),\s*)*(?:$LinkPattern|\[\[$FreeLinkPattern\]\]))/cg) {
      return Subscribe($1, $4);
    } elsif (m/\GMy\s+subscribed\s+pages:\s*((?:(?:$LinkPattern|\[\[$FreeLinkPattern\]\]),\s*)*(?:$LinkPattern|\[\[$FreeLinkPattern\]\]))/cg) {
      return Subscribe($1, '');
    } elsif (m/\GMy\s+subscribed\s+categories:\s*((?:(?:$LinkPattern|\[\[$FreeLinkPattern\]\]),\s*)*(?:$LinkPattern|\[\[$FreeLinkPattern\]\]))/cg) {
      return Subscribe('', $1);
    }
  }
  return;
}

sub Subscribe {
  my ($pages, $categories) = @_;
  my $oldpos = pos;
  my @pageslist = map {
    if (/\[\[$FreeLinkPattern\]\]/) {
      FreeToNormal($1);
    } else {
      $_;
    }
  } split(/\s*,\s*/, $pages);
  my @catlist = map {
    if (/\[\[$FreeLinkPattern\]\]/) {
      FreeToNormal($1);
    } else {
      $_;
    }
  } split(/\s*,\s*/, $categories);
  my $regexp;
  $regexp .= '^(' . join('|', @pageslist) . ")\$" if @pageslist;
  $regexp .= '|' if @pageslist and @catlist;
  $regexp .= '(' . join('|', @catlist) . ')' if @catlist;
  pos = $oldpos;
  my $html = 'My subscribed ';
  return $html unless @pageslist or @catlist;
  $html .= 'pages: ' . join(', ', map { my $x = $_; $x =~ s/_/ /g; $x; } @pageslist)
    if @pageslist;
  $html .= ', ' if @pageslist and @catlist;
  $html .= 'categories: ' . join(', ', map { my $x = $_; $x =~ s/_/ /g; $x; } @catlist)
    if @catlist;
  return ScriptLink('action=rc;rcfilteronly=' . $regexp, $html);
}
