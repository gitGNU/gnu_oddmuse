# Copyright (C) 2006  Alex Schroeder <alex@emacswiki.org>
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

require 't/test.pl';
package OddMuse;
use Test::More tests => 6;

clear_pages();

update_page('foo_moo', 'foo_bar');
test_page(update_page('yadda', '<include "foo moo">'),
	  qq{<div class="include foo_moo"><p>foo_bar</p></div>});
test_page(update_page('yadda', '<include text "foo moo">'),
	  qq{<pre class="include foo_moo">foo_bar\n</pre>});
test_page(update_page('yadda', '<include "yadda">'),
	  qq{<strong>Recursive include of yadda!</strong>});
update_page('yadda', '<include "foo moo">');
test_page(update_page('dada', '<include "yadda">'),
	  qq{<div class="include yadda"><div class="include foo_moo"><p>foo_bar</p></div></div>});
test_page(update_page('foo_moo', '<include "dada">'),
	  qq{<strong>Recursive include of foo_moo!</strong>});
test_page(update_page('bar', '<include "foo_moo">'),
	  qq{<strong>Recursive include of foo_moo!</strong>});
