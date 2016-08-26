#! /usr/bin/perl
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

use CGI qw/:standard/;
use CGI::Carp qw(fatalsToBrowser);
use Encode;

sub translate {
  my $str = shift;
  $str = encode('utf-8', decode('latin-1', $str));
  my @letters = split(//, $str);
  my @safe = ('a' .. 'z', 'A' .. 'Z', '0' .. '9', '-', '_', '.', '!', '~', '*', "'", '(', ')',
	      ':', '/', '?', ';', '&');
  foreach my $letter (@letters) {
    my $pattern = quotemeta($letter);
    if (not grep(/$pattern/, @safe)) {
      $letter = uc(sprintf("%%%02x", ord($letter)));
    }
  }
  return join('', @letters);
}

if (not param('url')) {
  print header(),
    start_html('Latin-1 to UTF-8 Escapes'),
    h1('Latin-1 to UTF-8 Escapes'),
    p('Translates URLs containing URL-encoded Latin-1 to ',
      'URLs containing URL-encoded UTF-8 and redirects to it.'),
    start_form(-method=>'GET'),
    p('URL: ', textfield('url', '', 70)),
    p(submit()),
    end_form(),
    end_html();
  exit;
}

my $str = param('url');

print redirect(translate($str));

# print $str, "\n";
# print translate($str), "\n";

# perl latin-1.pl url=http://www.emacswiki.org/cgi-bin/community/LangueFran%E7aise
