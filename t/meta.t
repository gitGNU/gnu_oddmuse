# Copyright (C) 2015  Alex Jakimenko <alex.jakimenko@gmail.com>
# Copyright (C) 2015  Alex Schroeder <alex@gnu.com>
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
use warnings;
use v5.10;
use utf8;

package OddMuse;
require 't/test.pl';
use Test::More tests => 11;
use File::Basename;
use Pod::Strip;
use Pod::Simple::TextContent;

my @modules = grep { $_ ne 'modules/404handler.pl' } <modules/*.pl>;
my @badModules;

@badModules = grep { (stat $_)[2] != oct '100644' } @modules;
unless (ok(@badModules == 0, 'Consistent file permissions of modules')) {
  diag(sprintf "$_ has %o but 100644 was expected", (stat $_)[2]) for @badModules;
  diag("▶▶▶ Use this command to fix it: chmod 644 @badModules");
}

@badModules = grep { ReadFile($_) !~ / ^ use \s+ strict; /xm } @modules;
unless (ok(@badModules == 0, '"use strict;" in modules')) {
  diag(qq{$_ has no "use strict;"}) for @badModules;
}

 SKIP: {
   skip '"use v5.10;" tests, we are not doing "use v5.10;" everywhere yet', 1;
   @badModules = grep { ReadFile($_) !~ / ^ use \s+ v5\.10; /xm } @modules;
   unless (ok(@badModules == 0, '"use v5.10;" in modules')) {
     diag(qq{$_ has no "use v5.10;"}) for @badModules;
     diag(q{Minimum perl version for the core is v5.10, it seems like there is no reason not to have "use v5.10;" everywhere else.});
   }
}

@badModules = grep {
  my $code = ReadFile($_);
  # warn "Looking at $_: " . length($code);

  # check Perl source code
  my $perl;
  my $pod_stripper = Pod::Strip->new;
  $pod_stripper->output_string(\$perl);
  $pod_stripper->parse_string_document($code);
  $perl =~ s/#.*//g;
  my $bad_perl = $perl !~ / ^ use \s+ utf8; /xm && $perl =~ / ([[:^ascii:]]+) /x;
  diag(qq{$_ has no "use utf8;" but contains non-ASCII characters in Perl code, eg. "$1"}) if $bad_perl;

  # check POD
  my $pod;
  my $pod_text = Pod::Simple::TextContent->new;
  $pod_text->output_string(\$pod);
  $pod_text->parse_string_document($code);
  my $bad_pod = $code !~ / ^ =encoding \s+ utf8 /xm && $pod =~ / ([[:^ascii:]]+) /x;
  diag(qq{$_ has no "=encoding utf8" but contains non-ASCII characters in POD, eg. "$1"}) if $bad_pod;
  $bad_perl || $bad_pod;
} @modules;
ok(@badModules == 0, 'utf8 in modules');

 SKIP: {
   skip 'documentation tests, we did not try to document every module yet', 1;
   @badModules = grep { ReadFile($_) !~ / ^ AddModuleDescription\(' [^\']+ ', /xm } @modules;
   unless (ok(@badModules == 0, 'link to the documentation in modules')) {
     diag(qq{$_ has no link to the documentation}) for @badModules;
   }
}

@badModules = grep { ReadFile($_) =~ / ^ package \s+ OddMuse; /xmi } @modules;
unless (ok(@badModules == 0, 'no "package OddMuse;" in modules')) {
  diag(qq{$_ has "package OddMuse;"}) for @badModules;
  diag(q{When we do "do 'somemodule.pl';" it ends up being in the same namespace of a caller, so there is no need to use "package OddMuse;"});
}

@badModules = grep { ReadFile($_) =~ / ^ use \s+ vars /xm } @modules;
unless (ok(@badModules == 0, 'no "use vars" in modules')) {
  diag(qq{$_ is using "use vars"}) for @badModules;
  diag('▶▶▶ Use "our ($var, ...)" instead of "use vars qw($var ...)"');
  diag(q{▶▶▶ Use this command to do automatic conversion: perl -0pi -e 's/^([\t ]*)use vars qw\s*\(\s*(.*?)\s*\);/$x = $2; $x =~ s{(?<=\w)\b(?!$)}{,}g;"$1our ($x);"/gems' } . "@badModules");
}

@badModules = grep { ReadFile($_) =~ / [ \t]+ $ /xm } @modules;
unless (ok(@badModules == 0, 'no trailing whitespace in modules')) {
  diag(qq{$_ has trailing whitespace}) for @badModules;
  diag(q{▶▶▶ Use this command to do automatic trailing whitespace removal: perl -pi -e 's/[ \t]+$//g' } . "@badModules");
}

@badModules = grep { ReadFile($_) =~ / This (program|file) is free software /x } @modules;
unless (ok(@badModules == 0, 'license is specified in every module')) {
  diag(qq{$_ has no license specified}) for @badModules;
}

@badModules = grep {
  my ($name, $path, $suffix) = fileparse($_, '.pl');
  ReadFile($_) !~ /^AddModuleDescription\('$name.pl'/mx;
 } @modules;
unless (ok(@badModules == 0, 'AddModuleDescription is used in every module')) {
  diag(qq{$_ does not use AddModuleDescription}) for @badModules;
}

# we have to use shell to redirect the output :(
@badModules = grep { system("perl -cT \Q$_\E > /dev/null 2>&1") != 0 } @modules;
unless (ok(@badModules == 0, 'modules are syntatically correct')) {
  diag(qq{$_ has syntax errors}) for @badModules;
  diag("▶▶▶ Use this command to see the problems: perl -c @badModules");
}