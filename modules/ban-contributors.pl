# Copyright (C) 2013  Alex Schroeder <alex@gnu.org>

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

=head1 Ban Contributors Extension

This module adds "Ban contributors" to the administration page. If you
click on it, it will list all the recent contributors to the page
you've been looking at. Each contributor (IP or hostname) will be
compared to the list of regular expressions on the C<BannedHosts> page
(see C<$BannedHosts>). If the contributor is already banned, this is
mentioned. If the contributor is not banned, you'll see a button
allowing you to ban him or her immediately. If you click the button,
the IP or hostname will be added to the C<BannedHosts> page for you.

=cut

$ModulesDescription .= '<p><a href="http://git.savannah.gnu.org/cgit/oddmuse.git/tree/modules/ban-contributors.pl">ban-contributors.pl</a>, see <a href="http://www.oddmuse.org/cgi-bin/oddmuse/Ban_Contributors_Extension">Ban Contributors Extension</a></p>';

push(@MyAdminCode, \&BanMenu);

sub BanMenu {
  my ($id, $menuref, $restref) = @_;
  if ($id and UserIsAdmin()) {
    push(@$menuref, ScriptLink('action=ban;id=' . UrlEncode($id),
			       T('Ban contributors')));
  }
}

$Action{ban} = \&DoBanHosts;

sub IsHostBanned {
  my ($host, $regexps) = @_;
  foreach my $regexp (@$regexps) {
    return $host if ($host =~ /$regexp/i);
  }
}

sub DoBanHosts {
  my $id = shift;
  my $host = GetParam('host', '');
  if ($host) {
    $host =~ s/\./\\./g;
    SetParam('text', GetPageContent($BannedHosts)
	     . "^" . $host . " # " . CalcDay($Now) . " "
	     . NormalToFree($id) . "\n");
    SetParam('summary', NormalToFree($id));
    DoPost($BannedHosts);
  } else {
    ValidIdOrDie($id);
    print GetHeader('', Ts('Ban Contributors to %s', NormalToFree($id)));
    SetParam('rcidonly', $id);
    SetParam('all', 1);
    my %contrib = ();
    for my $line (GetRcLines()) {
      $contrib{$line->[4]}->{$line->[5]} = 1 if $line->[4];
    }
    my @regexps = ();
    foreach (split(/\n/, GetPageContent($BannedHosts))) {
      if (/^\s*([^#]\S+)/) { # all lines except empty lines and comments, trim whitespace
	push(@regexps, $1);
      }
    }
    print '<div class="content ban">';
    foreach (sort(keys %contrib)) {
      my $name = $_;
      delete $contrib{$_}{''};
      $name .= " (" . join(", ", sort(keys(%{$contrib{$_}}))) . ")";
      if (IsHostBanned($_, \@regexps)) {
	print $q->p(Ts("%s is banned", $name));
      } else {
	print GetFormStart(undef, 'get', 'ban'),
	  GetHiddenValue('action', 'ban'),
	  GetHiddenValue('id', $id),
	  GetHiddenValue('host', $_),
	  GetHiddenValue('recent_edit', 'on'),
	  $q->p($name, $q->submit(T('Ban!'))), $q->end_form();
      }
    }
  }
  PrintFooter();
}

=head2 Rollback

If you are an admin and rolled back a single page, this extension will
list the URLs your rollback removed (assuming that those URLs are part
of the spam) and it will allow you to provide a regular expression
that will be added to BannedHosts.

=cut

*OldBanContributorsWriteRcLog = *WriteRcLog;
*WriteRcLog = *NewBanContributorsWriteRcLog;

sub NewBanContributorsWriteRcLog {
  my ($tag, $id, $to) = @_;
  if ($tag eq '[[rollback]]' and $id and $to > 0
      and $OpenPageName eq $id and UserIsAdmin()) {
    # we currently have the clean page loaded, so we need to reload
    # the spammed revision (there is a possible race condition here)
    my ($old) = GetTextRevision($Page{revision}-1, 1);
    my %urls = map {$_ => 1 } $old =~ /$UrlPattern/og;
    # we open the file again to force a load of the despammed page
    foreach my $url ($Page{text} =~ /$UrlPattern/og) {
      delete($urls{$url});
    }
    if (keys %urls) {
      print $q->p(T("These URLs were rolled back. Perhaps you want to add a regular expression to banned hosts?"));
      print $q->pre(join("\n", sort keys %urls));
      print GetFormStart(undef, 'get', 'ban'),
	    GetHiddenValue('action', 'ban'),
	    GetHiddenValue('id', $id),
	    GetHiddenValue('recent_edit', 'on'),
	    $q->p($q->label({-for=>'host'}, T('Regular expression:')), " ",
		  $q->textfield(-name=>'host', -size=>30), " ",
		  $q->submit(T('Ban!'))),
	    $q->end_form();
    };
  };
  return OldBanContributorsWriteRcLog(@_);
}
