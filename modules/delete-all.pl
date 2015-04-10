# Copyright (C) 2006-2013  Alex Schroeder <alex@gnu.org>

# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <http://www.gnu.org/licenses/>.

use strict;

AddModuleDescription('delete-all.pl');

our (%Page, $Now, $OpenPageName, %LockOnCreation);
our ($DeleteAge);

$DeleteAge = 172800; # 2*24*60*60

*OldDelPageDeletable = *PageDeletable;
*PageDeletable = *NewDelPageDeletable;

# All pages will be deleted after two days of inactivity!
sub NewDelPageDeletable {
  return 1 if $Now - $Page{ts} > $DeleteAge
    and not $LockOnCreation{$OpenPageName};
  return OldDelPageDeletable(@_);
}
