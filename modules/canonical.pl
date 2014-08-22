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

AddModuleDescription('canonical.pl', 'Canonical Names');

use utf8;

*OldCanonicalResolveId = *ResolveId;
*ResolveId = *NewCanonicalResolveId;

my %CanonicalName = ();

sub NewCanonicalResolveId {
  my $id = shift;
  my ($class, $resolved, $title, $exists) = OldCanonicalResolveId($id);
  return ($class, $resolved, $title, $exists) if $resolved;
  if (not %CanonicalName) {
    foreach my $page (AllPagesList()) {
      $CanonicalName{CanonicalName($page)} = $page;
    }
  }
  if ($CanonicalName{$id}) {
    return ('local canonical', $CanonicalName{$id}, $CanonicalName{$id}, undef);
  }
}

# If the page AlexSchröder exists, [[alexschroder]] will link to it.

sub CanonicalName {
  my $str = shift;
  $str =~ tr/äáàâëéèêïíìîöóòôüúùû/aaaaeeeeiiiioooouuuu/;
  $str = lc($str);
  return $str;
}
