# Copyright (C) 2007–2015  Alex Schroeder <alex@gnu.org>
#
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

require 't/test.pl';
package OddMuse;
use Test::More tests => 12;

clear_pages();

AppendStringToFile($ConfigFile, "\$StyleSheetPage = 'css';\n");

# Default
xpath_test(get_page('HomePage'),
	   '//link[@type="text/css"][@rel="stylesheet"][@href="http://www.oddmuse.org/default.css"]');

# StyleSheetPage
update_page('css', "em { font-weight: bold; }", 'some css', 0, 1);
$page = get_page('HomePage');
negative_xpath_test($page,
	   '//link[@type="text/css"][@rel="stylesheet"][@href="http://www.oddmuse.org/default.css"]');
xpath_test($page,
	   '//link[@type="text/css"][@rel="stylesheet"][@href="http://localhost/wiki.pl?action=browse;id=css;raw=1;mime-type=text/css"]');

# StyleSheet option
AppendStringToFile($ConfigFile, "\$StyleSheet = 'http://example.org/test.css';\n");
$page = get_page('HomePage');
negative_xpath_test($page,
	   '//link[@type="text/css"][@rel="stylesheet"][@href="http://www.oddmuse.org/default.css"]',
	   '//link[@type="text/css"][@rel="stylesheet"][@href="http://localhost/wiki.pl?action=browse;id=css;raw=1;mime-type=text/css"]');
xpath_test($page,
	   '//link[@type="text/css"][@rel="stylesheet"][@href="http://example.org/test.css"]');

# Parameter
$page = get_page('action=browse id=HomePage css=http://example.org/my.css');
negative_xpath_test($page,
	   '//link[@type="text/css"][@rel="stylesheet"][@href="http://www.oddmuse.org/default.css"]',
	   '//link[@type="text/css"][@rel="stylesheet"][@href="http://localhost/wiki.pl?action=browse;id=css;raw=1;mime-type=text/css"]',
	   '//link[@type="text/css"][@rel="stylesheet"][@href="http://example.org/test.css"]');
xpath_test($page,
	   '//link[@type="text/css"][@rel="stylesheet"][@href="http://example.org/my.css"]');

$page = get_page('action=browse id=HomePage css=http://example.org/my.css%20http://example.org/your.css');
xpath_test($page,
	   '//link[@type="text/css"][@rel="stylesheet"][@href="http://example.org/my.css"]',
	   '//link[@type="text/css"][@rel="stylesheet"][@href="http://example.org/your.css"]');
