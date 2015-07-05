# Copyright (C) 2014–2015  Alex Schroeder <alex@gnu.org>
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

require 't/test.pl';
package OddMuse;
use Test::More tests => 2;

test_page(update_page('Test', 'Hallo'), 'Hallo');
print qx(perl scripts/raw.pl --page $PageDir --dir $DataDir/raw/);
my ($status, $data) = ReadFile("$DataDir/raw/Test"); # not fatal
ok($status && $data eq "Hallo\n", "raw Test created");
