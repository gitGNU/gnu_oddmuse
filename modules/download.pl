# Copyright (C) 2004  Alex Schroeder <alex@emacswiki.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the
#    Free Software Foundation, Inc.
#    59 Temple Place, Suite 330
#    Boston, MA 02111-1307 USA

$ModulesDescription .= '<p>$Id: download.pl,v 1.4 2004/10/15 14:09:32 as Exp $</p>';

push( @MyRules, \&DownloadSupportRule );

# [[download:page name]]
# [[download:page name|alternate title]]

sub DownloadSupportRule {
  if (m!\G(\[\[download:$FreeLinkPattern\|?(.*)\]\])!gc) {
    Dirty($1);
    print GetDownloadLink($2, undef, undef, $3);
    return '';
  }
  return undef;
}
