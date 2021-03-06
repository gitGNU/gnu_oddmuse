# Copyright (C) 2006  Alex Schroeder <alex@emacswiki.org>
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

AddModuleDescription('grep.pl');

our ($q, @MyRules);

push(@MyRules, \&GrepRule);

sub GrepRule {
  if (/\G(&lt;grep "(.*?)"&gt;)/cgis) {
    # <search "regexp">
    Clean(CloseHtmlEnvironments());
    Dirty($1);
    my $oldpos = pos;
    print '<ul class="grep">';
    PrintGrep($2);
    print '</ul>';
    pos = $oldpos; # restore \G after searching
    return '';
  }
  return;
}

sub PrintGrep {
  my $regexp = shift;
  foreach my $id (AllPagesList()) {
    my $text = GetPageContent($id);
    next if (TextIsFile($text)); # skip files
    while ($text =~ m{($regexp)}gi) {
      print $q->li(GetPageLink($id) . ': ' . $1);
    }
  }
}
