# Copyright (C) 2007  Alex Schroeder <alex@gnu.org>
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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;

AddModuleDescription('context.pl', 'Calendar Extension');

our ($q, @Debugging, $UserGotoBar, @MyInitVariables);
push (@MyInitVariables, \&ContextMenuItem);

sub ContextMenuItem {
  my $id = GetId();
  if (defined &Cal and $id =~ /^(\d\d\d\d-\d\d)-\d\d/) {
    $UserGotoBar .= ScriptLink("action=collect;match=%5e$1",
			       $1,
			       "local collection month");
  }
}

push (@Debugging, sub {
	if (not defined &Cal) {
	  print $q->p("context.pl requires calendar.pl");
	}});
