# Copyright (C) 2012  Alex Schroeder <alex@gnu.org>
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
# along with this program. If not, see <http://www.gnu.org/licenses/>.

require 't/test.pl';
package OddMuse;
use Test::More tests => 4;
use utf8; # tests contain UTF-8 characters and it matters

clear_pages();
add_module('tex.pl');

test_page(update_page('Example', '4\times7 right\copyright a\inftyb'),
	  qw(4×7 right© a∞b));

ok($Tex{'\textreferencemark'}, "TeX patterns ok");

# Create the table of documentation:
# binmode(STDOUT, ':encoding(UTF-8)');
# my $i = 1;
# foreach (sort keys %Tex) {
#   printf "||%s || %s ", $_, $Tex{$_};
#   if ($i % 5 == 0) {
#     print "||\n";
#   }
#   $i++;
# }
