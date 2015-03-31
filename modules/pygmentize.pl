# Copyright (C) 2015  Alex-Daniel Jakimenko <alex.jakimenko@gmail.com>
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

use strict;
# use warnings;
use v5.10;
use utf8;

package OddMuse;

AddModuleDescription('pygmentize.pl', 'Pygmentize Extension');

our ($q, $bol, %RuleOrder, @MyRules);

push(@MyRules, \&PygmentizeRule);
$RuleOrder{\&PygmentizeRule} = -60;

sub PygmentizeRule {
  if ($bol && m/\G\{\{\{(\w+)?[ \t]*\n(.*?)\n\}\}\}[ \t]*(\n|$)/cgs) {
    my $lexer = $1;
    my $contents = $2;
    return CloseHtmlEnvironments() . DoPygmentize($contents, $lexer) . AddHtmlEnvironment('p');
  }
  return;
}

sub DoPygmentize {
  my ($contents, $lexer) = @_;
  $lexer = "-l \Q$lexer\E" if $lexer; # should be already safe, but \Q \E just because I'm paranoid
  $lexer ||= '-g'; # -g for autodetect
  my $options = 'whitespace:spaces=true,tabs=true'; # TODO make this configurable
  CreateDir($TempDir);
  $contents = UnquoteHtml($contents);

  RequestLockDir('pygmentize') or return '';
  WriteStringToFile("$TempDir/pygmentize", $contents);
  my $output = `pygmentize $lexer -f html -O encoding=utf8 -O noclasses -F \Q$options\E \Q$TempDir/pygmentize\E`;
  ReleaseLockDir('pygmentize');

  utf8::decode($output);
  return $output;
}
