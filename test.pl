#!/usr/bin/perl

# Copyright (C) 2004, 2005, 2006  Alex Schroeder <alex@emacswiki.org>
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

use XML::LibXML;
use Encode;

# Import the functions

package OddMuse;
$RunCGI = 0;    # don't print HTML on stdout
$UseConfig = 0; # don't read module files
do 'wiki.pl';
Init();

my ($passed, $failed) = (0, 0);
my $resultfile = "/tmp/test-markup-result-$$";
my $redirect;
undef $/;
$| = 1; # no output buffering

sub url_encode {
  my $str = shift;
  return '' unless $str;
  my @letters = split(//, $str);
  my @safe = ('a' .. 'z', 'A' .. 'Z', '0' .. '9', '-', '_', '.'); # shell metachars are unsafe
  foreach my $letter (@letters) {
    my $pattern = quotemeta($letter);
    if (not grep(/$pattern/, @safe)) {
      $letter = sprintf("%%%02x", ord($letter));
    }
  }
  return join('', @letters);
}

print "* means that a page is being updated\n";
sub update_page {
  my ($id, $text, $summary, $minor, $admin, @rest) = @_;
  print '*';
  my $pwd = $admin ? 'foo' : 'wrong';
  $id = url_encode($id);
  $text = url_encode($text);
  $summary = url_encode($summary);
  $minor = $minor ? 'on' : 'off';
  my $rest = join(' ', @rest);
  $redirect = `perl wiki.pl Save=1 title=$id summary=$summary recent_edit=$minor text=$text pwd=$pwd $rest`;
  $output = `perl wiki.pl action=browse id=$id`;
  # just in case a new page got created or NearMap or InterMap
  $IndexInit = 0;
  $NearInit = 0;
  $InterInit = 0;
  $RssInterwikiTranslateInit = 0;
  InitVariables();
  return $output;
}

print "+ means that a page is being retrieved\n";
sub get_page {
  print '+';
  open(F,"perl wiki.pl @_ |");
  my $output = <F>;
  close F;
  return $output;
}

print ". means a test\n";
sub test_page {
  my $page = shift;
  my $printpage = 0;
  foreach my $str (@_) {
    print '.';
    if ($page =~ /$str/) {
      $passed++;
    } else {
      $failed++;
      $printpage = 1;
      print "\nSimple Test: Did not find \"", $str, '"';
    }
  }
  print "\n\nPage content:\n", $page, "\n" if $printpage;
}

sub test_page_negative {
  my $page = shift;
  my $printpage = 0;
  foreach my $str (@_) {
    print '.';
    if ($page =~ /$str/) {
      $failed++;
      $printpage = 1;
      print "\nSimple negative Test: Found \"", $str, '"';
    } else {
      $passed++;
    }
  }
  print "\n\nPage content:\n", $page, "\n" if $printpage;
}

sub get_text_via_xpath {
  my ($page, $test) = @_;
  $page =~ s/^.*?<html>/<html>/s; # strip headers
  my $parser = XML::LibXML->new();
  my $doc;
  eval { $doc = $parser->parse_html_string($page) };
  if ($@) {
    print "Could not parse html: $@\n", $page, "\n\n";
    $failed += 1;
  } else {
    print '.';
    my $nodelist;
    eval { $nodelist = $doc->findnodes($test) };
    if ($@) {
      $failed++;
      print "\nXPATH Test: failed to run $test: $@\n";
    } elsif ($nodelist->size()) {
      $passed++;
      return $nodelist->string_value();
    } else {
      $failed++;
      print "\nXPATH Test: No matches for $test\n";
      $page =~ s/^.*?<body/<body/s;
      print substr($page,0,30000), "\n";
    }
  }
}


sub xpath_test {
  my ($page, @tests) = @_;
  $page =~ s/^.*?<html>/<html>/s; # strip headers
  my $parser = XML::LibXML->new();
  my $doc;
  eval { $doc = $parser->parse_html_string($page) };
  if ($@) {
    print "Could not parse html: ", substr($page,0,100), "\n";
    $failed += @tests;
  } else {
    foreach my $test (@tests) {
      print '.';
      my $nodelist;
      eval { $nodelist = $doc->findnodes($test) };
      if ($@) {
	$failed++;
	print "\nXPATH Test: failed to run $test: $@\n";
      } elsif ($nodelist->size()) {
	$passed++;
      } else {
	$failed++;
	print "\nXPATH Test: No matches for $test\n";
	$page =~ s/^.*?<body/<body/s; # strip
	print substr($page,0,30000), "\n";
      }
    }
  }
}

sub negative_xpath_test {
  my ($page, @tests) = @_;
  $page =~ s/^.*?<html>/<html>/s; # strip headers
  my $parser = XML::LibXML->new();
  my $doc = $parser->parse_html_string($page);
  foreach my $test (@tests) {
    print '.';
    my $nodelist = $doc->findnodes($test);
    if (not $nodelist->size()) {
      $passed++;
    } else {
      $failed++;
      $printpage = 1;
      print "\nXPATH Test: Unexpected matches for $test\n";
    }
  }
}

sub apply_rules {
  my $input = shift;
  local *STDOUT;
  $output = '';
  open(STDOUT, '>', \$output) or die "Can't open memory file: $!";
  $FootnoteNumber = 0;
  ApplyRules(QuoteHtml($input), 1);
  return $output;
}


sub xpath_run_tests {
  # translate embedded newlines (other backslashes remain untouched)
  my %New;
  foreach (keys %Test) {
    $Test{$_} =~ s/\\n/\n/g;
    my $new = $Test{$_};
    s/\\n/\n/g;
    $New{$_} = $new;
  }
  # Note that the order of tests is not specified!
  my $output;
  foreach my $input (keys %New) {
    my $output = apply_rules($input);
    xpath_test("<div>$output</div>", $New{$input});
  }
}

sub test_match {
  my ($input, @tests) = @_;
  my $output = apply_rules($input);
  foreach my $str (@tests) {
    print '.';
    if ($output =~ /$str/) {
      $passed++;
    } else {
      $failed++;
      $printpage = 1;
      print "\n\n---- input:\n", $input,
	    "\n---- output:\n", $output,
            "\n---- instead of:\n", $str, "\n----\n";
    }
  }
}

sub run_tests {
  # translate embedded newlines (other backslashes remain untouched)
  my %New;
  foreach (keys %Test) {
    $Test{$_} =~ s/\\n/\n/g;
    my $new = $Test{$_};
    s/\\n/\n/g;
    $New{$_} = $new;
  }
  # Note that the order of tests is not specified!
  foreach my $input (keys %New) {
    print '.';
    my $output = apply_rules($input);
    if ($output eq $New{$input}) {
      $passed++;
    } else {
      $failed++;
      print "\n\n---- input:\n", $input,
	    "\n---- output:\n", $output,
            "\n---- instead of:\n", $New{$input}, "\n----\n";
    }
  }
}

sub remove_rule {
  my $rule = shift;
  my @list = ();
  my $found = 0;
  foreach my $item (@MyRules) {
    if ($item ne $rule) {
      push @list, $item;
    } else {
      $found = 1;
    }
  }
  die "Rule not found" unless $found;
  @MyRules = @list;
}

sub add_module {
  my $mod = shift;
  mkdir $ModuleDir unless -d $ModuleDir;
  my $dir = `/bin/pwd`;
  chop($dir);
  symlink("$dir/modules/$mod", "$ModuleDir/$mod") or die "Cannot symlink $mod: $!"
    unless -l "$ModuleDir/$mod";
  do "$ModuleDir/$mod";
  @MyRules = sort {$RuleOrder{$a} <=> $RuleOrder{$b}} @MyRules;
}

sub remove_module {
  my $mod = shift;
  mkdir $ModuleDir unless -d $ModuleDir;
  unlink("$ModuleDir/$mod") or die "Cannot unlink: $!";
}

sub clear_pages {
  system('/bin/rm -rf /tmp/oddmuse');
  die "Cannot remove /tmp/oddmuse!\n" if -e '/tmp/oddmuse';
  mkdir '/tmp/oddmuse';
  open(F,'>/tmp/oddmuse/config');
  print F "\$AdminPass = 'foo';\n";
  # this used to be the default in earlier CGI.pm versions
  print F "\$ScriptName = 'http://localhost/wiki.pl';\n";
  print F "\$SurgeProtection = 0;\n";
  close(F);
  $ScriptName = 'http://localhost/test.pl'; # different!
  $IndexInit = 0;
  %IndexHash = ();
  $InterSiteInit = 0;
  %InterSite = ();
  $NearSiteInit = 0;
  %NearSite = ();
  %NearSearch = ();
}

# Create temporary data directory as expected by the script

my $str;

goto $ARGV[0] if $ARGV[0];

$ENV{'REMOTE_ADDR'} = 'test-markup';

# --------------------

major:
print '[major]';

clear_pages();
# start with minor
update_page('bar', 'one', '', 1); # lastmajor is undef
test_page(get_page('action=browse id=bar diff=1'), 'No diff available', 'one', 'Last major edit',
	  'diff=1;id=bar;diffrevision=1');
test_page(get_page('action=browse id=bar diff=2'), 'No diff available', 'one', 'Last edit');
update_page('bar', 'two', '', 1); # lastmajor is undef
test_page(get_page('action=browse id=bar diff=1'), 'No diff available', 'two', 'Last major edit',
	  'diff=1;id=bar;diffrevision=1');
test_page(get_page('action=browse id=bar diff=2'), 'one', 'two', 'Last edit');
update_page('bar', 'three'); # lastmajor is 3
test_page(get_page('action=browse id=bar diff=1'), 'two', 'three', 'Last edit');
test_page(get_page('action=browse id=bar diff=2'), 'two', 'three', 'Last edit');
update_page('bar', 'four'); # lastmajor is 4
test_page(get_page('action=browse id=bar diff=1'), 'three', 'four', 'Last edit');
test_page(get_page('action=browse id=bar diff=2'), 'three', 'four', 'Last edit');
# start with major
major1:
clear_pages();
update_page('bla', 'one'); # lastmajor is 1
test_page(get_page('action=browse id=bla diff=1'), 'No diff available', 'one', 'Last edit');
test_page(get_page('action=browse id=bla diff=2'), 'No diff available', 'one', 'Last edit');
update_page('bla', 'two', '', 1); # lastmajor is 1
test_page(get_page('action=browse id=bla diff=1'), 'No diff available', 'two', 'Last major edit',
	  'diff=1;id=bla;diffrevision=1');
test_page(get_page('action=browse id=bla diff=2'), 'one', 'two', 'Last edit');
update_page('bla', 'three'); # lastmajor is 3
test_page(get_page('action=browse id=bla diff=1'), 'two', 'three', 'Last edit');
test_page(get_page('action=browse id=bla diff=2'), 'two', 'three', 'Last edit');
update_page('bla', 'four', '', 1); # lastmajor is 3
test_page(get_page('action=browse id=bla diff=1'), 'two', 'three', 'Last major edit',
	  'diff=1;id=bla;diffrevision=3');
test_page(get_page('action=browse id=bla diff=2'), 'three', 'four', 'Last edit');
update_page('bla', 'five'); # lastmajor is 5
test_page(get_page('action=browse id=bla diff=1'), 'four', 'five', 'Last edit');
test_page(get_page('action=browse id=bla diff=2'), 'four', 'five', 'Last edit');
update_page('bla', 'six'); # lastmajor is 6
test_page(get_page('action=browse id=bla diff=1'), 'five', 'six', 'Last edit');
test_page(get_page('action=browse id=bla diff=2'), 'five', 'six', 'Last edit');

# --------------------

revisions:
print '[revisions]';

clear_pages();

## Test revision and diff stuff

update_page('KeptRevisions', 'first');
update_page('KeptRevisions', 'second');
update_page('KeptRevisions', 'third');
update_page('KeptRevisions', 'fourth', '', 1);
update_page('KeptRevisions', 'fifth', '', 1);

# Show the current revision

test_page(get_page(KeptRevisions),
	  'KeptRevisions',
	  'fifth');

# Show the other revision

test_page(get_page('action=browse revision=2 id=KeptRevisions'),
	  'Showing revision 2',
	  'second');

test_page(get_page('action=browse revision=1 id=KeptRevisions'),
	 'Showing revision 1',
	  'first');

# Show the current revision if an inexisting revision is asked for

test_page(get_page('action=browse revision=9 id=KeptRevisions'),
	  'Revision 9 not available \(showing current revision instead\)',
	  'fifth');

# Disable cache and request the correct last major diff
test_page(get_page('action=browse diff=1 id=KeptRevisions cache=0'),
	  'Difference between revision 2 and revision 3',
	  'second',
	  'third');

# Show a diff from the history page comparing two specific revisions
test_page(get_page('action=browse diff=1 revision=4 diffrevision=2 id=KeptRevisions'),
	  'Difference between revision 2 and revision 4',
	  'second',
	  'fourth');

# Show no difference
update_page('KeptRevisions', 'second');
test_page(get_page('action=browse diff=1 revision=6 diffrevision=2 id=KeptRevisions'),
	  'Difference between revision 2 and revision 6',
	  'The two revisions are the same');

# --------------------

diff:
print '[diff]';

clear_pages();

# Highlighting differences
update_page('xah', "When we judge people in society, often, we can see people's true nature not by the official defenses and behaviors, but by looking at the statistics (past records) of their behavior and the circumstances it happens.\n"
	    . "For example, when we look at the leader in human history. Great many of them have caused thousands and millions of intentional deaths. Some of these leaders are hated by many, yet great many of them are adored and admired and respected... (ok, i'm digressing...)\n");
update_page('xah', "When we judge people in society, often, we can see people's true nature not by the official defenses and behaviors, but by looking at some subtleties, and also the statistics (past records) of their behavior and the circumstances they were in.\n"
	    . "For example, when we look at leaders in history. Great many of them have caused thousands and millions of intentional deaths. Some of these leaders are hated by many, yet great many of them are adored and admired and respected... (ok, i'm digressing...)\n");
test_page(get_page('action=browse diff=1 id=xah'),
	  '<strong class="changes">it happens</strong>',
	  '<strong class="changes">the leader</strong>',
	  '<strong class="changes">human</strong>',
	  '<strong class="changes">some subtleties, and also</strong>',
	  '<strong class="changes">they were in</strong>',
	  '<strong class="changes">leaders</strong>',
	 );

# --------------------

rollback:
print '[rollback]';

clear_pages();

# old revisions
update_page('InnocentPage', 'Innocent.', 'good guy zero');
update_page('NicePage', 'Friendly content.', 'good guy one');
update_page('OtherPage', 'Other cute content 1.', 'another good guy');
update_page('OtherPage', 'Other cute content 2.', 'another good guy');
update_page('OtherPage', 'Other cute content 3.', 'another good guy');
update_page('OtherPage', 'Other cute content 4.', 'another good guy');
update_page('OtherPage', 'Other cute content 5.', 'another good guy');
update_page('OtherPage', 'Other cute content 6.', 'another good guy');
update_page('OtherPage', 'Other cute content 7.', 'another good guy');
update_page('OtherPage', 'Other cute content 8.', 'another good guy');
update_page('OtherPage', 'Other cute content 9.', 'another good guy');
update_page('OtherPage', 'Other cute content 10.', 'another good guy');
update_page('OtherPage', 'Other cute content 11.', 'another good guy');
# good revisions -- need a different timestamp than the old revisions!
sleep(1);
update_page('InnocentPage', 'Lamb.', 'good guy zero');
update_page('OtherPage', 'Other cute content 12.', 'another good guy');
update_page('MinorPage', 'Dumdidu', 'tester');
# last good revision -- needs a different timestamp than the good revisions!
sleep(1);
update_page('NicePage', 'Nice content.', 'good guy two');
# bad revisions -- need a different timestamp than the last good revision!
sleep(1);
update_page('NicePage', 'Evil content.', 'vandal one');
update_page('OtherPage', 'Other evil content.', 'another vandal');
update_page('NicePage', 'Bad content.', 'vandal two');
update_page('EvilPage', 'Spam!', 'vandal three');
update_page('AnotherEvilPage', 'More Spam!', 'vandal four');
update_page('AnotherEvilPage', 'Still More Spam!', 'vandal five');
update_page('MinorPage', 'Ramtatam', 'testerror', 1);

test_page(get_page('NicePage'), 'Bad content');
test_page(get_page('InnocentPage'), 'Lamb');

$to = get_text_via_xpath(get_page('action=rc all=1 pwd=foo'),
			 '//strong[text()="good guy two"]/preceding-sibling::a[@class="rollback"]/attribute::href');
$to =~ /action=rollback;to=([0-9]+)/;
$to = $1;

test_page(get_page("action=rollback to=$to"), 'username is required');
test_page(get_page("action=rollback to=$to username=me"), 'restricted to administrators');
test_page(get_page("action=rollback to=$to pwd=foo"),
	  'Rolling back changes',
	  'EvilPage</a> rolled back',
	  'AnotherEvilPage</a> rolled back',
	  'MinorPage</a> rolled back',
	  'NicePage</a> rolled back',
	  'OtherPage</a> rolled back');

test_page(get_page('NicePage'), 'Nice content');
test_page(get_page('OtherPage'), 'Other cute content 12');
test_page(get_page('EvilPage'), 'DeletedPage');
test_page(get_page('AnotherEvilPage'), 'DeletedPage');
test_page(get_page('InnocentPage'), 'Lamb');

my $rc = get_page('action=rc all=1 showedit=1 pwd=foo'); # this includes rollback info and rollback links

# check all revisions of NicePage in recent changes
xpath_test($rc,
	'//li/span[@class="time"]/following-sibling::span[@class="new"][text()="new"]/following-sibling::a[@class="rollback"][text()="rollback"]/following-sibling::a[@class="revision"][@href="http://localhost/wiki.pl?action=browse;id=NicePage;revision=1"][text()="NicePage"]/following-sibling::span[@class="dash"]/following-sibling::strong[text()="good guy one"]',
	'//li/span[@class="time"]/following-sibling::a[@class="diff"][@href="http://localhost/wiki.pl?action=browse;diff=2;id=NicePage;diffrevision=2"][text()="diff"]/following-sibling::a[@class="rollback"][text()="rollback"]/following-sibling::a[@class="revision"][@href="http://localhost/wiki.pl?action=browse;id=NicePage;revision=2"][text()="NicePage"]/following-sibling::span[@class="dash"]/following-sibling::strong[text()="good guy two"]',
	'//li/span[@class="time"]/following-sibling::a[@class="diff"][@href="http://localhost/wiki.pl?action=browse;diff=2;id=NicePage;diffrevision=3"][text()="diff"]/following-sibling::a[@class="rollback"][text()="rollback"]/following-sibling::a[@class="revision"][@href="http://localhost/wiki.pl?action=browse;id=NicePage;revision=3"][text()="NicePage"]/following-sibling::span[@class="dash"]/following-sibling::strong[text()="vandal one"]',
	'//li/span[@class="time"]/following-sibling::a[@class="diff"][@href="http://localhost/wiki.pl?action=browse;diff=2;id=NicePage;diffrevision=4"][text()="diff"]/following-sibling::a[@class="rollback"]/following-sibling::a[@class="revision"][@href="http://localhost/wiki.pl?action=browse;id=NicePage;revision=4"][text()="NicePage"]/following-sibling::span[@class="dash"]/following-sibling::strong[text()="vandal two"]',
	'//li/span[@class="time"]/following-sibling::a[@class="diff"][@href="http://localhost/wiki.pl?action=browse;diff=2;id=NicePage"][text()="diff"]/following-sibling::a[@class="rollback"][text()="rollback"]/following-sibling::a[@class="revision"][@href="http://localhost/wiki.pl?action=browse;id=NicePage"][text()="NicePage"]/following-sibling::span[@class="dash"]/following-sibling::strong[contains(text(),"Rollback to")]',
	# check that the minor spam is reverted with a minor rollback
	'//li/span[@class="time"]/following-sibling::span[@class="new"][text()="new"]/following-sibling::a[@class="rollback"][text()="rollback"]/following-sibling::a[@class="revision"][@href="http://localhost/wiki.pl?action=browse;id=MinorPage;revision=1"][text()="MinorPage"]/following-sibling::span[@class="dash"]/following-sibling::strong[text()="tester"]',
	'//li/span[@class="time"]/following-sibling::a[@class="diff"][@href="http://localhost/wiki.pl?action=browse;diff=2;id=MinorPage;diffrevision=2"][text()="diff"]/following-sibling::a[@class="rollback"][text()="rollback"]/following-sibling::a[@class="revision"][@href="http://localhost/wiki.pl?action=browse;id=MinorPage;revision=2"][text()="MinorPage"]/following-sibling::span[@class="dash"]/following-sibling::strong[text()="testerror"]/following-sibling::em[text()="(minor)"]',
	   '//li/span[@class="time"]/following-sibling::a[@class="diff"][@href="http://localhost/wiki.pl?action=browse;diff=2;id=MinorPage"][text()="diff"]/following-sibling::a[@class="rollback"][text()="rollback"]/following-sibling::a[@class="revision"][@href="http://localhost/wiki.pl?action=browse;id=MinorPage"][text()="MinorPage"]/following-sibling::span[@class="dash"]/following-sibling::strong[contains(text(),"Rollback to")]/following-sibling::em[text()="(minor)"]',
	  );

# test that ordinary RC doesn't show the rollback stuff
update_page('Yoga', 'Ommmm', 'peace');

$page = get_page('action=rc raw=1');
test_page($page,
	  "title: NicePage\ndescription: good guy two\n",
	  "title: MinorPage\ndescription: tester\n",
	  "title: OtherPage\ndescription: another good guy\n",
	  "title: InnocentPage\ndescription: good guy zero\n",
	  "title: Yoga\ndescription: peace\n",
	  );
test_page_negative($page,
		   "rollback",
		   "Rollback",
		   "EvilPage",
		   "AnotherEvilPage",
		  );

# --------------------

history:
print '[history]';

clear_pages();

$page = get_page('action=history id=hist');
test_page($page,
	  'No other revisions available',
	  'View current revision',
	  'View all changes');
test_page_negative($page,
		   'View other revisions',
		   'Mark this page for deletion');

test_page(update_page('hist', 'testing', 'test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary'),
	  'testing',
	  'action=history',
	  'View other revisions');

test_page_negative(get_page('action=history id=hist'),
		   'Mark this page for deletion');
$page = get_page('action=history id=hist username=me');
test_page($page,
	  'test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary test summary',
	  'View current revision',
	  'View all changes',
	  'current',
	  'Mark this page for deletion');
test_page_negative($page,
		   'No other revisions available',
		   'View other revisions',
		   'rollback');

test_page(update_page('hist', 'Tesla', 'Power'),
	  'Tesla',
	  'action=history',
	  'View other revisions');
$page = get_page('action=history id=hist username=me');
test_page($page,
	  'test summary',
	  'Power',
	  'View current revision',
	  'View all changes',
	  'current',
	  'rollback',
	  'action=rollback;to=',
	  'Mark this page for deletion');
test_page_negative($page,
		   'Tesla',
		   'No other revisions available',
		   'View other revisions');

# --------------------

pagenames:
print '[pagenames]';

clear_pages();

update_page('.dotfile', 'old content', 'older summary');
update_page('.dotfile', 'some content', 'some summary');
test_page(get_page('.dotfile'), 'some content');
test_page(get_page('action=browse id=.dotfile revision=1'), 'old content');
test_page(get_page('action=history id=.dotfile'), 'older summary', 'some summary');

# --------------------

clusters:
print '[clusters]';

clear_pages();

AppendStringToFile($ConfigFile, "\$PageCluster = 'Cluster';\n");

update_page('ClusterIdea', 'This is just a page.', 'one');
update_page('ClusterIdea', "This is just a page.\nBut somebody has to do it.", 'two');
update_page('ClusterIdea', "This is just a page.\nNobody wants it.", 'three', 1);
update_page('ClusterIdea', "MainPage\nThis is just a page.\nBut somebody has to do it.", 'four');

test_page(get_page('action=rc'), 'Cluster.*MainPage');

test_page(get_page('action=rc all=1'), qw(Cluster.*MainPage ClusterIdea.*two ClusterIdea.*one));

test_page(get_page('action=rc all=1 showedit=1'), qw(Cluster.*MainPage ClusterIdea.*three
						     ClusterIdea.*two ClusterIdea.*one));

@Test = split('\n',<<'EOT');
Finally the main page
Updates in the last [0-9]+ days
diff.*ClusterIdea.*history.*four
for.*MainPage.*only
1 day
action=browse;id=MainPage;rcclusteronly=MainPage;days=1;all=0;showedit=0
EOT

update_page('MainPage', 'Finally the main page.', 'main summary');
test_page(get_page('action=browse id=MainPage rcclusteronly=MainPage'), @Test);

@Test = split('\n',<<'EOT');
Finally the main page
Updates in the last [0-9]+ days
diff.*ClusterIdea.*four
for.*MainPage.*only
1 day
EOT

test_page(get_page('action=browse id=MainPage rcclusteronly=MainPage showedit=1'),
	  (@Test, 'action=browse;id=MainPage;rcclusteronly=MainPage;days=1;all=0;showedit=1'));
test_page(get_page('action=browse id=MainPage rcclusteronly=MainPage all=1'),
	  (@Test, 'action=browse;id=MainPage;rcclusteronly=MainPage;days=1;all=1;showedit=0'));

@Test = split('\n',<<'EOT');
Finally the main page
Updates in the last [0-9]+ days
diff.*ClusterIdea.*five
diff.*ClusterIdea.*four
for.*MainPage.*only
1 day
action=browse;id=MainPage;rcclusteronly=MainPage;days=1;all=1;showedit=1
EOT

update_page('ClusterIdea', "MainPage\nSomebody has to do it.", 'five', 1);
test_page(get_page('action=browse id=MainPage rcclusteronly=MainPage all=1 showedit=1'), @Test);

test_page(get_page('action=rss'), 'action=browse;id=MainPage;rcclusteronly=MainPage');

update_page('OtherIdea', "MainPage\nThis is another page.\n", 'new page in cluster');
$page = get_page('action=rc raw=1');
test_page($page, 'title: MainPage', 'description: OtherIdea: new page in cluster',
	  'description: main summary');
test_page_negative($page, 'ClusterIdea');

# --------------------

rss:
print '[rss]';

# create simple config file

use Cwd;
$dir = cwd;
$uri = "file://$dir";

# some xpath tests
update_page('RSS', "<rss $uri/heise.rdf>");
$page = get_page('RSS');
xpath_test($page, Encode::encode_utf8('//a[@title="999"][@href="http://www.heise.de/tp/deutsch/inhalt/te/15886/1.html"][text()="Berufsverbot für Mediendesigner?"]'));

@Test = split('\n',<<'EOT');
<div class="rss"><ul><li>
Experimentell bestätigt:
http://www.heise.de/tp/deutsch/inhalt/lis/15882/1.html
Clash im Internet?
http://www.heise.de/tp/deutsch/special/med/15787/1.html
Die Einheit der Umma gegen die jüdische Weltmacht
http://www.heise.de/tp/deutsch/special/ost/15879/1.html
Im Krieg mit dem Satan
http://www.heise.de/tp/deutsch/inhalt/co/15880/1.html
Der dritte Mann
http://www.heise.de/tp/deutsch/inhalt/co/15876/1.html
Leicht neben dem Ziel
http://www.heise.de/tp/deutsch/inhalt/mein/15867/1.html
Wale sollten Nordkorea meiden
http://www.heise.de/tp/deutsch/inhalt/co/15878/1.html
Afghanistan-Krieg und Irak-Besatzung haben al-Qaida gestärkt
http://www.heise.de/tp/deutsch/inhalt/co/15874/1.html
Der mit dem Dinosaurier tanzt
http://www.heise.de/tp/deutsch/inhalt/lis/15863/1.html
Terroranschlag überschattet das Genfer Abkommen
http://www.heise.de/tp/deutsch/special/ost/15873/1.html
"Barwatch" in Kanada
http://www.heise.de/tp/deutsch/inhalt/te/15871/1.html
Die Türken kommen!
http://www.heise.de/tp/deutsch/special/irak/15870/1.html
Neue Regelungen zur Telekommunikationsüberwachung
http://www.heise.de/tp/deutsch/inhalt/te/15869/1.html
Ein Lied vom Tod
http://www.heise.de/tp/deutsch/inhalt/kino/15862/1.html
EOT

test_page($page, @Test);

# RSS 2.0

update_page('RSS', "<rss $uri/flickr.xml>");
test_page(get_page('RSS'),
	  join('(.|\n)*', # verify the *order* of things.
	       'href="http://www.flickr.com/photos/broccoli/867118/"',
	       'href="http://www.flickr.com/photos/broccoli/867075/"',
	       'href="http://www.flickr.com/photos/seuss/864332/"',
	       'href="http://www.flickr.com/photos/redking/851171/"',
	       'href="http://www.flickr.com/photos/redking/851168/"',
	       'href="http://www.flickr.com/photos/redking/851167/"',
	       'href="http://www.flickr.com/photos/redking/851166/"',
	       'href="http://www.flickr.com/photos/redking/851165/"',
	       'href="http://www.flickr.com/photos/bibo/844085/"',
	       'href="http://www.flickr.com/photos/theunholytrinity/867312/"'),
	  join('(.|\n)*',
	       'title="2004-10-14 09:34:47 "',
	       'title="2004-10-14 09:28:11 "',
	       'title="2004-10-14 05:08:17 "',
	       'title="2004-10-13 10:00:34 "',
	       'title="2004-10-13 10:00:30 "',
	       'title="2004-10-13 10:00:27 "',
	       'title="2004-10-13 10:00:25 "',
	       'title="2004-10-13 10:00:22 "',
	       'title="2004-10-12 23:38:14 "',
	       'title="2004-10-10 10:09:06 "'),
	  join('(.|\n)*',
	       '>The Hydra<',
	       '>The War On Hydra<',
	       '>Nation Demolished<',
	       '>Drummers<',
	       '>Death<',
	       '>Audio Terrorists<',
	       '>Crowds<',
	       '>Assholes<',
	       '>iraq_saddam03<',
	       '>brudermann<'));

@Test = split('\n',<<'EOT');
Fania All Stars - Bamboleo
http://www.audioscrobbler.com/music/Fania\+All\+Stars/_/Bamboleo
EOT

update_page('RSS', "<rss $uri/kensanata.xml>");
test_page(get_page('RSS'), @Test);

@Test = split('\n',<<'EOT');
PRNewswire: Texas Software Startup, Serenity Systems, Advises Business Users to Get Off Windows
http://linuxtoday.com/story.php3\?sn=9443
LinuxPR: MyDesktop Launches Linux Software Section
http://linuxtoday.com/story.php3\?sn=9442
LinuxPR: Franklin Institute Science Museum Chooses Linux
http://linuxtoday.com/story.php3\?sn=9441
Yellow Dog Linux releases updated am-utils
http://linuxtoday.com/story.php3\?sn=9440
LinuxPR: LinuxCare Adds Laser5 Linux To Roster of Supported Linux Distributions
http://linuxtoday.com/story.php3\?sn=9439
EOT

update_page('RSS', "<rss $uri/linuxtoday.rdf>");
test_page(get_page('RSS'), @Test);

@Test = split('\n',<<'EOT');
Xskat 3.1
http://freshmeat.net/news/1999/09/01/936224942.html
Java Test Driver 1.1
http://freshmeat.net/news/1999/09/01/936224907.html
WaveLAN/IEEE driver 1.0.1
http://freshmeat.net/news/1999/09/01/936224545.html
macfork 1.0
http://freshmeat.net/news/1999/09/01/936224336.html
QScheme 0.2.2
http://freshmeat.net/news/1999/09/01/936223755.html
CompuPic 4.6 build 1018
http://freshmeat.net/news/1999/09/01/936223729.html
eXtace 1.1.16
http://freshmeat.net/news/1999/09/01/936223709.html
GTC 0.3
http://freshmeat.net/news/1999/09/01/936223686.html
RocketJSP 0.9c
http://freshmeat.net/news/1999/09/01/936223646.html
Majik 3D 0.0/M3
http://freshmeat.net/news/1999/09/01/936223622.html
EOT

update_page('RSS', "<rss $uri/fm.rdf>");
test_page(get_page('RSS'), @Test);

@Test = split('\n',<<'EOT');
GTKeyboard 0.85
http://freshmeat.net/news/1999/06/21/930003829.html
EOT

update_page('RSS', "<rss $uri/rss1.0.rdf>");
test_page(get_page('RSS'), @Test);

# Note, cannot identify BayleShanks as author in the mb.rdf
@Test = split('\n',<<'EOT');
MeatBall:LionKimbro
2003-10-24T22:49:33\+06:00
CommunityWiki:RecentNearChanges
http://www.usemod.com/cgi-bin/mb.pl\?LionKimbro
2003-10-24T21:02:53\+00:00
unified rc for here and meatball
<span class="contributor"><span> \. \. \. \. </span>AlexSchroeder</span>
http://www.emacswiki.org/cgi-bin/community\?action=browse;id=RecentNearChanges;revision=1
EOT

update_page('RSS', "<rss $uri/mb.rdf $uri/community.rdf>");
test_page(get_page('RSS'), @Test);

# --------------------

aggregation:
print '[aggregation]';

clear_pages();
add_module('aggregate.pl');

update_page('InnocentPage', 'We are innocent!');
update_page('NicePage', 'You are nice.');
update_page('OtherPage', 'This is off-topic.');
update_page('Front_Page', q{Hello!
<aggregate "NicePage" "OtherPage">
The End.});

$page = get_page('Front_Page');
xpath_test($page, '//div[@class="content browse"]/p[text()="Hello! "]',
	   '//div[@class="aggregate journal"]/div[@class="page"]/h2/a[@class="local"][text()="NicePage"]',
	   '//div[@class="aggregate journal"]/div[@class="page"]/h2/a[@class="local"][text()="OtherPage"]',
	   '//div[@class="page"]/p[text()="You are nice."]',
	   '//div[@class="page"]/p[text()="This is off-topic."]',
	   '//div[@class="content browse"]/p[text()=" The End."]');

$page = get_page('action=aggregate id=Front_Page');
test_page($page, '<title>NicePage</title>',
	  '<title>OtherPage</title>',
	  '<link>http://localhost/wiki.pl/NicePage</link>',
	  '<link>http://localhost/wiki.pl/OtherPage</link>',
	  '<description>&lt;p&gt;You are nice.&lt;/p&gt;</description>',
	  '<description>&lt;p&gt;This is off-topic.&lt;/p&gt;</description>',
	  '<wiki:status>new</wiki:status>',
	  '<wiki:importance>major</wiki:importance>',
	  quotemeta('<wiki:history>http://localhost/wiki.pl?action=history;id=NicePage</wiki:history>'),
	  quotemeta('<wiki:diff>http://localhost/wiki.pl?action=browse;diff=1;id=NicePage</wiki:diff>'),
	  quotemeta('<wiki:history>http://localhost/wiki.pl?action=history;id=OtherPage</wiki:history>'),
	  quotemeta('<wiki:diff>http://localhost/wiki.pl?action=browse;diff=1;id=OtherPage</wiki:diff>'),
	  '<title>Wiki: Front Page</title>',
	  '<link>http://localhost/wiki.pl/Front_Page</link>',
	 );

remove_rule(\&AggregateRule);
delete $Action{aggregate};

# --------------------

redirection:
print '[redirection]';
clear_pages();

update_page('Miles_Davis', 'Featuring [[John Coltrane]]'); # plain link
update_page('John_Coltrane', '#REDIRECT Coltrane'); # no redirect
update_page('Sonny_Stitt', '#REDIRECT [[Stitt]]'); # redirect
update_page('Keith_Jarret', 'Plays with [[Gary Peacock]]'); # link to perm. anchor
update_page('Jack_DeJohnette', 'A friend of [::Gary Peacock]'); # define perm. anchor

test_page(get_page('Miles_Davis'), ('Featuring', 'John Coltrane'));
test_page(get_page('John_Coltrane'), ('#REDIRECT Coltrane'));
test_page(get_page('Sonny_Stitt'),
	  ('Status: 302', 'Location: .*wiki.pl\?action=browse;oldid=Sonny_Stitt;id=Stitt'));
test_page(get_page('Keith_Jarret'),
	  ('Plays with', 'wiki.pl/Jack_DeJohnette#Gary_Peacock', 'Keith Jarret', 'Gary Peacock'));
test_page(get_page('Gary_Peacock'),
	  ('Status: 302', 'Location: .*wiki.pl/Jack_DeJohnette#Gary_Peacock'));
test_page(get_page('Jack_DeJohnette'),
	  ('A friend of', 'Gary Peacock', 'name="Gary_Peacock"', 'class="definition"',
	   'title="Click to search for references to this permanent anchor"'));
test_page(update_page('Jack_DeJohnette', 'A friend of Gary Peacock.'),
	  'A friend of Gary Peacock.');
test_page(get_page('Keith_Jarret'),
	  ('wiki.pl\?action=edit;id=Gary_Peacock'));

# --------------------

summary:
print '[summary]';
clear_pages();

update_page('sum', 'some [http://example.com content]');
test_page(get_page('action=rc raw=1'), 'description: some content');

# --------------------

recent_changes:
print '[recent changes]';
clear_pages();

$host1 = 'tisch';
$host2 = 'stuhl';
$ENV{'REMOTE_ADDR'} = $host1;
update_page('Mendacibombus', 'This is the place.', 'samba', 0, 0, ('username=berta'));
update_page('Bombia', 'This is the time.', 'tango', 0, 0, ('username=alex'));
$ENV{'REMOTE_ADDR'} = $host2;
update_page('Confusibombus', 'This is order.', 'ballet', 1, 0, ('username=berta'));
update_page('Mucidobombus', 'This is chaos.', 'tarantella', 0, 0, ('username=alex'));

@Positives = split('\n',<<'EOT');
for time\|place only
Mendacibombus.*samba
Bombia.*tango
EOT

@Negatives = split('\n',<<'EOT');
Confusibombus
ballet
Mucidobombus
tarantella
EOT

$page = get_page('action=rc rcfilteronly=time\|place');
test_page($page, @Positives);
test_page_negative($page, @Negatives);

@Positives = split('\n',<<'EOT');
Mucidobombus.*tarantella
EOT

@Negatives = split('\n',<<'EOT');
Mendacibombus
samba
Bombia
tango
Confusibombus
ballet
EOT

$page = get_page('action=rc rcfilteronly=order\|chaos');
test_page($page, @Positives);
test_page_negative($page, @Negatives);

@Positives = split('\n',<<'EOT');
EOT

@Negatives = split('\n',<<'EOT');
Mucidobombus
tarantella
Mendacibombus
samba
Bombia
tango
Confusibombus
ballet
EOT

$page = get_page('action=rc rcfilteronly=order%20chaos');
test_page($page, @Positives);
test_page_negative($page, @Negatives);

@Positives = split('\n',<<'EOT');
Mendacibombus.*samba
Bombia.*tango
EOT

@Negatives = split('\n',<<'EOT');
Mucidobombus
tarantella
Confusibombus
ballet
EOT

$page = get_page('action=rc rchostonly=tisch');
test_page($page, @Positives);
test_page_negative($page, @Negatives);

@Positives = split('\n',<<'EOT');
Mucidobombus.*tarantella
EOT

@Negatives = split('\n',<<'EOT');
Confusibombus
ballet
Bombia
tango
Mendacibombus
samba
EOT

$page = get_page('action=rc rchostonly=stuhl'); # no minor edits!
test_page($page, @Positives);
test_page_negative($page, @Negatives);

@Positives = split('\n',<<'EOT');
Mucidobombus.*tarantella
Confusibombus.*ballet
EOT

@Negatives = split('\n',<<'EOT');
Mendacibombus
samba
Bombia
tango
EOT

$page = get_page('action=rc rchostonly=stuhl showedit=1'); # with minor edits!
test_page($page, @Positives);
test_page_negative($page, @Negatives);

@Positives = split('\n',<<'EOT');
Mendacibombus.*samba
EOT

@Negatives = split('\n',<<'EOT');
Mucidobombus
tarantella
Bombia
tango
Confusibombus
ballet
EOT

$page = get_page('action=rc rcuseronly=berta');
test_page($page, @Positives);
test_page_negative($page, @Negatives);

@Positives = qw(Mucidobombus.*tarantella Bombia.*tango);

@Negatives = qw(Confusibombus ballet Mendacibombus samba);

$page = get_page('action=rc rcuseronly=alex');
test_page($page, @Positives);
test_page_negative($page, @Negatives);

@Positives = qw(Bombia.*tango);

@Negatives = qw(Mucidobombus tarantella Confusibombus ballet Mendacibombus samba);

$page = get_page('action=rc rcidonly=Bombia');
test_page($page, @Positives);
test_page_negative($page, @Negatives);

# --------------------

conflicts:
print '[conflicts]';

# Using the example files from the diff3 manual

my $lao_file = q{The Way that can be told of is not the eternal Way;
The name that can be named is not the eternal name.
The Nameless is the origin of Heaven and Earth;
The Named is the mother of all things.
Therefore let there always be non-being,
  so we may see their subtlety,
And let there always be being,
  so we may see their outcome.
The two are the same,
But after they are produced,
  they have different names.
};

my $lao_file_1 = q{The Tao that can be told of is not the eternal Tao;
The name that can be named is not the eternal name.
The Nameless is the origin of Heaven and Earth;
The Named is the mother of all things.
Therefore let there always be non-being,
  so we may see their subtlety,
And let there always be being,
  so we may see their outcome.
The two are the same,
But after they are produced,
  they have different names.
};
my $lao_file_2 = q{The Way that can be told of is not the eternal Way;
The name that can be named is not the eternal name.
The Nameless is the origin of Heaven and Earth;
The Named is the mother of all things.
Therefore let there always be non-being,
  so we may see their simplicity,
And let there always be being,
  so we may see the result.
The two are the same,
But after they are produced,
  they have different names.
};

my $tzu_file = q{The Nameless is the origin of Heaven and Earth;
The named is the mother of all things.

Therefore let there always be non-being,
  so we may see their subtlety,
And let there always be being,
  so we may see their outcome.
The two are the same,
But after they are produced,
  they have different names.
They both may be called deep and profound.
Deeper and more profound,
The door of all subtleties!
};

my $tao_file = q{The Way that can be told of is not the eternal Way;
The name that can be named is not the eternal name.
The Nameless is the origin of Heaven and Earth;
The named is the mother of all things.

Therefore let there always be non-being,
  so we may see their subtlety,
And let there always be being,
  so we may see their result.
The two are the same,
But after they are produced,
  they have different names.

  -- The Way of Lao-Tzu, tr. Wing-tsit Chan
};

clear_pages();

# simple edit

$ENV{'REMOTE_ADDR'} = 'confusibombus';
test_page(update_page('ConflictTest', $lao_file),
	  'The Way that can be told of is not the eternal Way');

# edit from another address should result in conflict warning

$ENV{'REMOTE_ADDR'} = 'megabombus';
test_page(update_page('ConflictTest', $tzu_file),
	  'The Nameless is the origin of Heaven and Earth');

# test cookie!
test_page($redirect, map { UrlEncode($_); }
	  ('This page was changed by somebody else',
           'Please check whether you overwrote those changes'));

# test normal merging -- first get oldtime, then do two conflicting edits
# we need to wait at least a second after the last test in order to not
# confuse oddmuse.

sleep(2);

update_page('ConflictTest', $lao_file);

$_ = `perl wiki.pl action=edit id=ConflictTest`;
/name="oldtime" value="([0-9]+)"/;
my $oldtime = $1;

sleep(2);

$ENV{'REMOTE_ADDR'} = 'confusibombus';
update_page('ConflictTest', $lao_file_1);

sleep(2);

# merge success has lines from both lao_file_1 and lao_file_2
$ENV{'REMOTE_ADDR'} = 'megabombus';
test_page(update_page('ConflictTest', $lao_file_2,
		      '', '', '', "oldtime=$oldtime"),
	  'The Tao that can be told of',     # file 1
	  'The name that can be named',      # both
	  'so we may see their simplicity'); # file 2

# test conflict during merging -- first get oldtime, then do two conflicting edits

sleep(2);

update_page('ConflictTest', $tzu_file);

$_ = `perl wiki.pl action=edit id=ConflictTest`;
/name="oldtime" value="([0-9]+)"/;
$oldtime = $1;

sleep(2);

$ENV{'REMOTE_ADDR'} = 'confusibombus';
update_page('ConflictTest', $tao_file);

sleep(2);

$ENV{'REMOTE_ADDR'} = 'megabombus';
test_page(update_page('ConflictTest', $lao_file,
		      '', '', '', "oldtime=$oldtime"),
	  q{<pre class="conflict">&lt;&lt;&lt;&lt;&lt;&lt;&lt; ancestor
=======
The Way that can be told of is not the eternal Way;
The name that can be named is not the eternal name.
&gt;&gt;&gt;&gt;&gt;&gt;&gt; other
</pre>},
	  q{<pre class="conflict">&lt;&lt;&lt;&lt;&lt;&lt;&lt; you
||||||| ancestor
They both may be called deep and profound.
Deeper and more profound,
The door of all subtleties!
=======

  -- The Way of Lao-Tzu, tr. Wing-tsit Chan
&gt;&gt;&gt;&gt;&gt;&gt;&gt; other
</pre>});

@Test = split('\n',<<'EOT');
This page was changed by somebody else
The changes conflict
EOT

test_page($redirect, map { UrlEncode($_); } @Test); # test cookie!

# test conflict during merging without merge! -- first get oldtime, then do two conflicting edits

AppendStringToFile($ConfigFile, "\$ENV{'PATH'} = '';\n");

sleep(2);

update_page('ConflictTest', $lao_file);

$_ = `perl wiki.pl action=edit id=ConflictTest`;
/name="oldtime" value="([0-9]+)"/;
$oldtime = $1;

sleep(2);

$ENV{'REMOTE_ADDR'} = 'confusibombus';
update_page('ConflictTest', $lao_file_1);

sleep(2);

# merge not available -- must look for message
$ENV{'REMOTE_ADDR'} = 'megabombus';
test_page(update_page('ConflictTest', $lao_file_2,
		      '', '', '', "oldtime=$oldtime"),
	  'The Way that can be told of is not the eternal Way',   # file 2
	  'so we may see their simplicity',                       # file 2
	  'so we may see the result');                            # file 2

test_page($redirect, map { UrlEncode($_) }
	  ('This page was changed by somebody else',
           'Please check whether you overwrote those changes')); # test cookie!

# --------------------

html_cache:
print '[html cache]';

### Maintenance with cache resetting

clear_pages();
$str = 'This is a WikiLink.';

# this setting produces no link.
AppendStringToFile($ConfigFile, "\$WikiLinks = 0;\n");
test_page(update_page('CacheTest', $str, '', 1), $str);

# now change the setting, you still get no link because the cache has
# not been updated.
AppendStringToFile($ConfigFile, "\$WikiLinks = 1;\n");
test_page(get_page('CacheTest'), $str);

# refresh the cache
test_page(get_page('action=clear pwd=foo'), 'Clear Cache');

# now there is a link
# This is a WikiLink<a class="edit" title="Click to edit this page" href="http://localhost/wiki.pl\?action=edit;id=WikiLink">\?</a>.
xpath_test(get_page('CacheTest'), '//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/wiki.pl?action=edit;id=WikiLink"][text()="?"]');

# --------------------

search_and_replace:
print '[search and replace]';

clear_pages();
add_module('mac.pl');

# Test search

update_page('SearchAndReplace', 'This is fooz and this is barz.', '', 1);
$page = get_page('search=fooz');
test_page($page,
	  '<h1>Search for: fooz</h1>',
	  '<p class="result">1 pages found.</p>',
	  'This is <strong>fooz</strong> and this is barz.');
xpath_test($page, '//span[@class="result"]/a[@class="local"][@href="http://localhost/wiki.pl/SearchAndReplace"][text()="SearchAndReplace"]');

# Brackets in the page name

test_page(update_page('Search (and replace)', 'Muu'),
	  'search=%22Search\+%5c\(and\+replace%5c\)%22');

# Make sure only admins can replace

test_page(get_page('search=foo replace=bar'),
	  'This operation is restricted to administrators only...');

# Simple replace where the replacement pattern is found

@Test = split('\n',<<'EOT');
<h1>Replaced: fooz -&gt; fuuz</h1>
<p class="result">1 pages found.</p>
This is <strong>fuuz</strong> and this is barz.
EOT

test_page(get_page('search=fooz replace=fuuz pwd=foo'), @Test);

# Replace with backreferences, where the replacement pattern is no longer found

test_page(get_page('search=([a-z]%2b)z replace=x%241 pwd=foo'), '0 pages found');
test_page(get_page('SearchAndReplace'), 'This is xfuu and this is xbar.');

# Create an extra page that should not be found
update_page('NegativeSearchTest', 'this page contains an ab');
update_page('NegativeSearchTestTwo', 'this page contains another ab');
test_page(get_page('search=xb replace=[xa]b pwd=foo'), '1 pages found'); # not two ab!
test_page(get_page('SearchAndReplace'), 'This is xfuu and this is \[xa\]bar.');

# Handle quoting
test_page(get_page('search=xfuu replace=/fuu/ pwd=foo'), '1 pages found'); # not two ab!
test_page(get_page('SearchAndReplace'), 'This is /fuu/ and this is \[xa\]bar.');
test_page(get_page('search=/fuu/ replace={{fuu}} pwd=foo'), '1 pages found');
test_page(get_page('SearchAndReplace'), 'This is {{fuu}} and this is \[xa\]bar.');

## Check headers especially the quoting of non-ASCII characters.

$page = update_page("Alexander_Schröder", "Edit [[Alexander Schröder]]!");
xpath_test($page,
	   Encode::encode_utf8('//h1/a[@title="Click to search for references to this page"][@href="http://localhost/wiki.pl?search=%22Alexander+Schr%c3%b6der%22"][text()="Alexander Schröder"]'),
	   Encode::encode_utf8('//a[@class="local"][@href="http://localhost/wiki.pl/Alexander_Schr%c3%b6der"][text()="Alexander Schröder"]'));

xpath_test(update_page('IncludeSearch',
		       "first line\n<search \"ab\">\nlast line"),
	   '//p[text()="first line "]', # note the NL -> SPC
	   '//div[@class="search"]/p/span[@class="result"]/a[@class="local"][@href="http://localhost/wiki.pl/NegativeSearchTest"][text()="NegativeSearchTest"]',
	   '//div[@class="search"]/p/span[@class="result"]/a[@class="local"][@href="http://localhost/wiki.pl/NegativeSearchTestTwo"][text()="NegativeSearchTestTwo"]',
	  '//p[text()=" last line"]'); # note the NL -> SPC

# --------------------

banning:
print '[banning]';

clear_pages();
$localhost = 'confusibombus';
$ENV{'REMOTE_ADDR'} = $localhost;

## Edit banned hosts as a normal user should fail

test_page(update_page('BannedHosts', "# Foo\n#Bar\n$localhost\n", 'banning me'),
	  'Describe the new page here');

## Edit banned hosts as admin should succeed

test_page(update_page('BannedHosts', "#Foo\n#Bar\n$localhost\n", 'banning me', 0, 1),
	  "Foo",
	  $localhost);

## Edit banned hosts as a normal user should fail

test_page(update_page('BannedHosts', "Something else.", 'banning me'),
	  "Foo",
	  $localhost);

## Try to edit another page as a banned user

test_page(update_page('BannedUser', 'This is a test which should fail.', 'banning test'),
	  'Describe the new page here');

## Try to edit the same page as a banned user with admin password

test_page(update_page('BannedUser', 'This is a test.', 'banning test', 0, 1),
	  "This is a test");

## Unbann myself again, testing the regexp

test_page(update_page('BannedHosts', "#Foo\n#Bar\n", 'banning me', 0, 1), "Foo", "Bar");

## Banning content

@Test = split('\n',<<'EOT');
banned text
wiki administrator
matched
See .*BannedContent.* for more information
EOT

update_page('BannedContent', "# cosa\nmafia\n#nostra\n", 'one banned word', 0, 1);
test_page(update_page('CriminalPage', 'This is about http://mafia.example.com'),
	  'Describe the new page here');
test_page($redirect, @Test);
test_page(update_page('CriminalPage', 'This is about http://nafia.example.com'),
	  "This is about", "http://nafia.example.com");
test_page(update_page('CriminalPage', 'This is about the cosa nostra'),
	  'cosa nostra');
test_page(update_page('CriminalPage', 'This is about the mafia'),
	  'This is about the mafia'); # not in an url

# --------------------

journal:
print '[journal]';

## Create diary pages

clear_pages();

update_page('2003-06-13', "Freitag");
update_page('2003-06-14', "Samstag");
update_page('2003-06-15', "Sonntag");

@Test = split('\n',<<'EOT');
This is my journal
2003-06-15
Sonntag
2003-06-14
Samstag
EOT

test_page(update_page('Summary', "This is my journal:\n\n<journal 2>"), @Test);
test_page(update_page('2003-01-01', "This is my journal -- recursive:\n\n<journal>"), @Test);
push @Test, 'journal';
test_page(update_page('2003-01-01', "This is my journal -- truly recursive:\n\n<journal>"), @Test);

test_page(update_page('Summary', "Counting down:\n\n<journal 2>"),
	  '2003-06-15(.|\n)*2003-06-14');

test_page(update_page('Summary', "Counting up:\n\n<journal 3 reverse>"),
	  '2003-01-01(.|\n)*2003-06-13(.|\n)*2003-06-14');

$page = update_page('Summary', "Counting down:\n\n<journal>");
test_page($page, '2003-06-15(.|\n)*2003-06-14(.|\n)*2003-06-13(.|\n)*2003-01-01');
negative_xpath_test($page, '//h1/a[not(text())]');

test_page(update_page('Summary', "Counting up:\n\n<journal reverse>"),
	  '2003-01-01(.|\n)*2003-06-13(.|\n)*2003-06-14(.|\n)*2003-06-15');

AppendStringToFile($ConfigFile, "\$JournalLimit = 2;\n\$ComentsPrefix = 'Talk about ';\n");

$page = update_page('Summary', "Testing the limit of two:\n\n<journal>");
test_page($page, '2003-06-15', '2003-06-14');
test_page_negative($page, '2003-06-13', '2003-01-01');

test_page(get_page('action=browse id=Summary pwd=foo'),
	  '2003-06-15(.|\n)*2003-06-14(.|\n)*2003-06-13(.|\n)*2003-01-01');

# --------------------

edit_lock:
print '[edit lock]';

clear_pages();
test_page(get_page('action=editlock'), 'operation is restricted');
test_page(get_page('action=editlock pwd=foo'), 'Edit lock created');
xpath_test(update_page('TestLock', 'mu!'),
	   '//a[@href="http://localhost/wiki.pl?action=password"][@class="password"][text()="This page is read-only"]');
test_page($redirect, '403 FORBIDDEN', 'Editing not allowed for TestLock');
test_page(get_page('action=editlock set=0'), 'operation is restricted');
test_page(get_page('action=editlock set=0 pwd=foo'), 'Edit lock removed');
RequestLockDir('main');
test_page(update_page('TestLock', 'mu!'), 'Describe the new page here');
test_page($redirect, 'Status: 503 SERVICE UNAVAILABLE',
	  'Could not get main lock', 'File exists',
	  'The lock was created (just now|1 second ago|2 seconds ago)');
test_page(update_page('TestLock', 'mu!'), 'Describe the new page here');
test_page($redirect, 'Status: 503 SERVICE UNAVAILABLE',
	  'Could not get main lock', 'File exists',
	  'The lock was created 3[0-5] seconds ago');

# --------------------

lock_on_creation:
print '[lock on creation]';

clear_pages();

## Create a sample page, and test for regular expressions in the output

$page = update_page('SandBox', 'This is a test.', 'first test');
test_page($page, 'SandBox', 'This is a test.');
xpath_test($page, '//h1/a[@title="Click to search for references to this page"][@href="http://localhost/wiki.pl?search=%22SandBox%22"][text()="SandBox"]');

## Test RecentChanges

@Test = split('\n',<<'EOT');
RecentChanges
first test
EOT

test_page(get_page('action=rc'), @Test);

## Updated the page

@Test = split('\n',<<'EOT');
RecentChanges
This is another test.
EOT

test_page(update_page('SandBox', 'This is another test.', 'second test'), @Test);

## Test RecentChanges

@Test = split('\n',<<'EOT');
RecentChanges
second test
EOT

test_page(get_page('action=rc'), @Test);

## Attempt to create InterMap page as normal user

@Test = split('\n',<<'EOT');
Describe the new page here
EOT

test_page(update_page('InterMap', " OddMuse http://www.emacswiki.org/cgi-bin/oddmuse.pl?\n", 'required'), @Test);

## Create InterMap page as admin

@Test = split('\n',<<'EOT');
OddMuse
http://www\.emacswiki\.org/cgi-bin/oddmuse\.pl
PlanetMath
http://planetmath\.org/encyclopedia/\%s\.html
EOT

test_page(update_page('InterMap', " OddMuse http://www.emacswiki.org/cgi-bin/oddmuse.pl?\n PlanetMath http://planetmath.org/encyclopedia/%s.html", 'required', 0, 1), @Test);

## Verify the InterMap stayed locked

@Test = split('\n',<<'EOT');
OddMuse
EOT

test_page(update_page('InterMap', "All your edits are blong to us!\n", 'required'), @Test);

# --------------------

despam_module:
print '[despam module]';

clear_pages();
add_module('despam.pl');

update_page('HilariousPage', "Ordinary text.");
update_page('HilariousPage', "Hilarious text.");
update_page('HilariousPage', "Spam from http://example.com.");

update_page('NoPage', "Spam from http://example.com.");

update_page('OrdinaryPage', "Spam from http://example.com.");
update_page('OrdinaryPage', "Ordinary text.");

update_page('ExpiredPage', "Spam from http://example.com.");
update_page('ExpiredPage', "More spam from http://example.com.");
update_page('ExpiredPage', "Still more spam from http://example.com.");

update_page('BannedContent', " example\\.com\n", 'required', 0, 1);

unlink('/tmp/oddmuse/keep/E/ExpiredPage/1.kp') or die "Cannot delete kept revision: $!";

@Test = split('\n',<<'EOT');
HilariousPage.*Revert to revision 2
NoPage.*Marked as DeletedPage
OrdinaryPage
ExpiredPage.*Cannot find unspammed revision
EOT

test_page(get_page('action=despam'), @Test);
test_page(get_page('ExpiredPage'), 'Still more spam');
test_page(get_page('OrdinaryPage'), 'Ordinary text');
test_page(get_page('NoPage'), 'DeletedPage');
test_page(get_page('HilariousPage'), 'Hilarious text');
test_page(get_page('BannedContent'), 'example\\\.com');

# --------------------

near:
print '[near]';

clear_pages();

CreateDir($NearDir);
WriteStringToFile("$NearDir/EmacsWiki", "AlexSchroeder\nFooBar\n");

update_page('InterMap', " EmacsWiki http://www.emacswiki.org/cgi-bin/wiki/%s\n",
	    'required', 0, 1);
update_page('NearMap', " EmacsWiki"
	    . " http://www.emacswiki.org/cgi-bin/emacs?action=index;raw=1"
	    . " http://www.emacswiki.org/cgi-bin/emacs?search=%s;raw=1;near=0\n",
	    'required', 0, 1);

xpath_test(update_page('FooBaz', "Try FooBar instead!\n"),
	   '//a[@class="near"][@title="EmacsWiki"][@href="http://www.emacswiki.org/cgi-bin/wiki/FooBar"][text()="FooBar"]',
	   '//div[@class="near"]/p/a[@class="local"][@href="http://localhost/wiki.pl/EditNearLinks"][text()="EditNearLinks"]/following-sibling::text()[string()=": "]/following-sibling::a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/wiki.pl?action=edit;id=FooBar"][text()="FooBar"]');

xpath_test(update_page('FooBar', "Test by AlexSchroeder!\n"),
	  '//div[@class="sister"]/p/a[@title="EmacsWiki:FooBar"][@href="http://www.emacswiki.org/cgi-bin/wiki/FooBar"]/img[@src="file:///tmp/oddmuse/EmacsWiki.png"][@alt="EmacsWiki:FooBar"]');

xpath_test(get_page('search=alexschroeder'),
	   '//p[text()="Near pages:"]',
	   '//a[@class="near"][@title="EmacsWiki"][@href="http://www.emacswiki.org/cgi-bin/wiki/AlexSchroeder"][text()="AlexSchroeder"]');

# --------------------

links:
print '[links]';

clear_pages();
add_module('links.pl');

update_page('InterMap', " Oddmuse http://www.emacswiki.org/cgi-bin/oddmuse.pl?\n",
	    'required', 0, 1);

update_page('a', 'Oddmuse:foo(no) [Oddmuse:bar] [Oddmuse:baz text] '
	    . '[Oddmuse:bar(no)] [Oddmuse:baz(no) text] '
	    . '[[Oddmuse:foo_(bar)]] [[[Oddmuse:foo (baz)]]] [[Oddmuse:foo (quux)|text]]');
$InterInit = 0;
InitVariables();

@Test = map { quotemeta } split('\n',<<'EOT');
"a" -> "Oddmuse:foo"
"a" -> "Oddmuse:bar"
"a" -> "Oddmuse:baz"
"a" -> "Oddmuse:foo_(bar)"
"a" -> "Oddmuse:foo (baz)"
"a" -> "Oddmuse:foo (quux)"
EOT

test_page_negative(get_page('action=links raw=1'), @Test);
test_page(get_page('action=links raw=1 inter=1'), @Test);

@Test = split('\n',<<'EOT');
//a[@class="local"][@href="http://localhost/wiki.pl/a"][text()="a"]
//a[@class="inter Oddmuse"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?foo"]/span[@class="site"][text()="Oddmuse"]/following-sibling::text()[string()=":"]/following-sibling::span[@class="page"][text()="foo"]
//a[@class="inter Oddmuse"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?bar"]/span[@class="site"][text()="Oddmuse"]/following-sibling::text()[string()=":"]/following-sibling::span[@class="page"][text()="bar"]
//a[@class="inter Oddmuse"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?baz"]/span[@class="site"][text()="Oddmuse"]/following-sibling::text()[string()=":"]/following-sibling::span[@class="page"][text()="baz"]
//a[@class="inter Oddmuse"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?foo_(bar)"]/span[@class="site"][text()="Oddmuse"]/following-sibling::text()[string()=":"]/following-sibling::span[@class="page"][text()="foo_(bar)"]
EOT

negative_xpath_test(get_page('action=links'), @Test);
xpath_test(get_page('action=links inter=1'), @Test);

AppendStringToFile($ConfigFile, "\$BracketWiki = 0;\n");

update_page('a', '[[b]] [[[c]]] [[d|e]] FooBar [FooBaz] [FooQuux fnord] ');

@Test1 = split('\n',<<'EOT');
"a" -> "b"
"a" -> "c"
"a" -> "FooBar"
"a" -> "FooBaz"
"a" -> "FooQuux"
EOT

@Test2 = split('\n',<<'EOT');
"a" -> "d"
EOT

$page = get_page('action=links raw=1');
test_page($page, @Test1);
test_page_negative($page, @Test2);

AppendStringToFile($ConfigFile, "\$BracketWiki = 1;\n");

update_page('a', '[[b]] [[[c]]] [[d|e]] FooBar [FooBaz] [FooQuux fnord] '
	    . 'http://www.oddmuse.org/ [http://www.emacswiki.org/] '
	    . '[http://www.communitywiki.org/ cw]');

@Test1 = split('\n',<<'EOT');
"a" -> "b"
"a" -> "c"
"a" -> "d"
"a" -> "FooBar"
"a" -> "FooBaz"
"a" -> "FooQuux"
EOT

@Test2 = split('\n',<<'EOT');
"a" -> "http://www.oddmuse.org/"
"a" -> "http://www.emacswiki.org/"
"a" -> "http://www.communitywiki.org/"
EOT

$page = get_page('action=links raw=1');
test_page($page, @Test1);
test_page_negative($page, @Test2);
$page = get_page('action=links raw=1 url=1');
test_page($page, @Test1, @Test2);
$page = get_page('action=links raw=1 links=0 url=1');
test_page_negative($page, @Test1);
test_page($page, @Test2);

# --------------------

download:
print '[download]';

clear_pages();

test_page_negative(get_page('HomePage'), 'logo');
AppendStringToFile($ConfigFile, "\$LogoUrl = '/pic/logo.png';\n");
xpath_test(get_page('HomePage'), '//a[@class="logo"]/img[@class="logo"][@src="/pic/logo.png"][@alt="[Home]"]');
AppendStringToFile($ConfigFile, "\$LogoUrl = 'Logo';\n");
xpath_test(get_page('HomePage'), '//a[@class="logo"]/img[@class="logo"][@src="Logo"][@alt="[Home]"]');
update_page('Logo', "#FILE image/png\niVBORw0KGgoAAAA");
xpath_test(get_page('HomePage'), '//a[@class="logo"]/img[@class="logo"][@src="http://localhost/wiki.pl/download/Logo"][@alt="[Home]"]');
AppendStringToFile($ConfigFile, "\$UsePathInfo = 0;\n");
xpath_test(get_page('HomePage'), '//a[@class="logo"]/img[@class="logo"][@src="http://localhost/wiki.pl?action=download;id=Logo"][@alt="[Home]"]');

# --------------------

link_pattern:
print '[link pattern]';

clear_pages();
$AllNetworkFiles = 1;

update_page('HomePage', "This page exists.");
update_page('InterMap', " Oddmuse http://www.emacswiki.org/cgi-bin/oddmuse.pl?\n PlanetMath http://planetmath.org/encyclopedia/%s.html", 'required', 0, 1);
$InterInit = 0;
$BracketWiki = 0; # old default
InitVariables();

%Test = split('\n',<<'EOT');
file://home/foo/tutorial.pdf
//a[@class="url file"][@href="file://home/foo/tutorial.pdf"][text()="file://home/foo/tutorial.pdf"]
file:///home/foo/tutorial.pdf
//a[@class="url file"][@href="file:///home/foo/tutorial.pdf"][text()="file:///home/foo/tutorial.pdf"]
image inline: [[image:HomePage]]
//a[@class="image"][@href="http://localhost/test.pl/HomePage"]/img[@class="upload"][@src="http://localhost/test.pl/download/HomePage"][@alt="HomePage"]
image inline: [[image:OtherPage]]
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=OtherPage;upload=1"][text()="?"]
traditional local link: HomePage
//a[@class="local"][@href="http://localhost/test.pl/HomePage"][text()="HomePage"]
traditional local link: OtherPage
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=OtherPage"][text()="?"]
traditional local link with extra brackets: [HomePage]
//a[@class="local number"][@title="HomePage"][@href="http://localhost/test.pl/HomePage"]/span/span[@class="bracket"][text()="["]/following-sibling::text()[string()="1"]/following-sibling::span[@class="bracket"][text()="]"]
traditional local link with extra brackets: [OtherPage]
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=OtherPage"][text()="?"]
traditional local link with other text: [HomePage homepage]
//a[@class="local"][@href="http://localhost/test.pl/HomePage"][text()="HomePage"]
traditional local link with other text: [OtherPage other page]
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=OtherPage"][text()="?"]
free link: [[home page]]
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=home_page"][text()="?"]
free link: [[other page]]
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=other_page"][text()="?"]
free link with extra brackets: [[[home page]]]
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=home_page"][text()="?"]
free link with extra brackets: [[[other page]]]
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=other_page"][text()="?"]
free link with other text: [[home page|da homepage]]
//text()[string()="free link with other text: [[home page|da homepage]]"]
free link with other text: [[other page|da other homepage]]
//text()[string()="free link with other text: [[other page|da other homepage]]"]
URL: http://www.oddmuse.org/
//a[@class="url http"][@href="http://www.oddmuse.org/"][text()="http://www.oddmuse.org/"]
URL in text http://www.oddmuse.org/ like this
//text()[string()="URL in text "]/following-sibling::a[@class="url http"][@href="http://www.oddmuse.org/"][text()="http://www.oddmuse.org/"]/following-sibling::text()[string()=" like this"]
URL in brackets: [http://www.oddmuse.org/]
//a[@class="url http number"][@href="http://www.oddmuse.org/"]/span/span[@class="bracket"][text()="["]/following-sibling::text()[string()="1"]/following-sibling::span[@class="bracket"][text()="]"]
URL in brackets with other text: [http://www.oddmuse.org/ oddmuse]
//a[@class="url http outside"][@href="http://www.oddmuse.org/"][text()="oddmuse"]
URL abbreviation: Oddmuse:Link_Pattern
//a[@class="inter Oddmuse"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?Link_Pattern"]/span[@class="site"][text()="Oddmuse"]/following-sibling::text()[string()=":"]/following-sibling::span[@class="page"][text()="Link_Pattern"]
URL abbreviation with extra brackets: [Oddmuse:Link_Pattern]
//a[@class="inter Oddmuse number"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?Link_Pattern"]/span/span[@class="bracket"][text()="["]/following-sibling::text()[string()="1"]/following-sibling::span[@class="bracket"][text()="]"]
URL abbreviation with other text: [Oddmuse:Link_Pattern link patterns]
//a[@class="inter Oddmuse outside"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?Link_Pattern"][text()="link patterns"]
URL abbreviation with meta characters: Oddmuse:Link+Pattern
//a[@class="inter Oddmuse"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?Link+Pattern"]/span[@class="site"][text()="Oddmuse"]/following-sibling::text()[string()=":"]/following-sibling::span[@class="page"][text()="Link+Pattern"]
URL abbreviation with meta characters and extra brackets: [Oddmuse:Link+Pattern]
//a[@class="inter Oddmuse number"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?Link+Pattern"]/span/span[@class="bracket"][text()="["]/following-sibling::text()[string()="1"]/following-sibling::span[@class="bracket"][text()="]"]
URL abbreviation with meta characters and other text: [Oddmuse:Link+Pattern link patterns]
//a[@class="inter Oddmuse outside"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?Link+Pattern"][text()="link patterns"]
free URL abbreviation: [[Oddmuse:Link Pattern]]
//a[@class="inter Oddmuse"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?Link%20Pattern"]/span[@class="site"][text()="Oddmuse"]/following-sibling::text()[string()=":"]/following-sibling::span[@class="page"][text()="Link Pattern"]
free URL abbreviation with extra brackets: [[[Oddmuse:Link Pattern]]]
//a[@class="inter Oddmuse number"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?Link%20Pattern"]/span/span[@class="bracket"][text()="["]/following-sibling::text()[string()="1"]/following-sibling::span[@class="bracket"][text()="]"]
free URL abbreviation with other text: [[Oddmuse:Link Pattern|link patterns]]
//a[@class="inter Oddmuse outside"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?Link%20Pattern"][text()="link patterns"]
free URL abbreviation with meta characters: [[Oddmuse:Link+Pattern]]
//a[@class="inter Oddmuse"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?Link%2bPattern"]/span[@class="site"][text()="Oddmuse"]/following-sibling::text()[string()=":"]/following-sibling::span[@class="page"][text()="Link+Pattern"]
free URL abbreviation with meta characters and extra brackets: [[[Oddmuse:Link+Pattern]]]
//a[@class="inter Oddmuse number"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?Link%2bPattern"]/span/span[@class="bracket"][text()="["]/following-sibling::text()[string()="1"]/following-sibling::span[@class="bracket"][text()="]"]
free URL abbreviation with meta characters and other text: [[Oddmuse:Link+Pattern|link patterns]]
//a[@class="inter Oddmuse outside"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?Link%2bPattern"][text()="link patterns"]
EOT

xpath_run_tests();

$AllNetworkFiles = 0;
$BracketWiki = 1;

%Test = split('\n',<<'EOT');
traditional local link: HomePage
//a[@class="local"][@href="http://localhost/test.pl/HomePage"][text()="HomePage"]
traditional local link: OtherPage
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=OtherPage"][text()="?"]
traditional local link with extra brackets: [HomePage]
//a[@class="local number"][@title="HomePage"][@href="http://localhost/test.pl/HomePage"]/span/span[@class="bracket"][text()="["]/following-sibling::text()[string()="1"]/following-sibling::span[@class="bracket"][text()="]"]
traditional local link with extra brackets: [OtherPage]
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=OtherPage"][text()="?"]
traditional local link with other text: [HomePage homepage]
//a[@class="local"][@href="http://localhost/test.pl/HomePage"][text()="homepage"]
traditional local link with other text: [OtherPage other page]
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=OtherPage"][text()="?"]
free link: [[home page]]
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=home_page"][text()="?"]
free link: [[other page]]
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=other_page"][text()="?"]
free link with extra brackets: [[[home page]]]
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=home_page"][text()="?"]
free link with extra brackets: [[[other page]]]
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=other_page"][text()="?"]
free link with other text: [[home page|da homepage]]
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=home_page"][text()="?"]
free link with other text: [[other page|da other homepage]]
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=other_page"][text()="?"]
URL: http://www.oddmuse.org/
//a[@class="url http"][@href="http://www.oddmuse.org/"][text()="http://www.oddmuse.org/"]
URL in brackets: [http://www.oddmuse.org/]
//a[@class="url http number"][@href="http://www.oddmuse.org/"]/span/span[@class="bracket"][text()="["]/following-sibling::text()[string()="1"]/following-sibling::span[@class="bracket"][text()="]"]
URL in brackets with other text: [http://www.oddmuse.org/ oddmuse]
//a[@class="url http outside"][@href="http://www.oddmuse.org/"][text()="oddmuse"]
URL abbreviation: Oddmuse:Link_Pattern
//a[@class="inter Oddmuse"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?Link_Pattern"]/span[@class="site"][text()="Oddmuse"]/following-sibling::text()[string()=":"]/following-sibling::span[@class="page"][text()="Link_Pattern"]
URL abbreviation with extra brackets: [Oddmuse:Link_Pattern]
//a[@class="inter Oddmuse number"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?Link_Pattern"]/span/span[@class="bracket"][text()="["]/following-sibling::text()[string()="1"]/following-sibling::span[@class="bracket"][text()="]"]
URL abbreviation with other text: [Oddmuse:Link_Pattern link patterns]
//a[@class="inter Oddmuse outside"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?Link_Pattern"][text()="link patterns"]
free URL abbreviation: [[Oddmuse:Link Pattern]]
//a[@class="inter Oddmuse"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?Link%20Pattern"]/span[@class="site"][text()="Oddmuse"]/following-sibling::text()[string()=":"]/following-sibling::span[@class="page"][text()="Link Pattern"]
free URL abbreviation with extra brackets: [[[Oddmuse:Link Pattern]]]
//a[@class="inter Oddmuse number"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?Link%20Pattern"]/span/span[@class="bracket"][text()="["]/following-sibling::text()[string()="1"]/following-sibling::span[@class="bracket"][text()="]"]
free URL abbreviation with other text: [[Oddmuse:Link Pattern|link pattern]]
//a[@class="inter Oddmuse outside"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?Link%20Pattern"][text()="link pattern"]
EOT

xpath_run_tests();

$BracketWiki = 0;

# --------------------

markup:
print '[markup]';

clear_pages();

update_page('InterMap', " OddMuse http://www.emacswiki.org/cgi-bin/oddmuse.pl?\n PlanetMath http://planetmath.org/encyclopedia/%s.html", 'required', 0, 1);
$InterInit = 0;
InitVariables();

# non links

$NetworkFile = 1;

%Test = split('\n',<<'EOT');
do not eat 0 from text
do not eat 0 from text
ordinary text
ordinary text
paragraph\n\nparagraph
paragraph<p>paragraph</p>
* one\n*two
<ul><li>one *two</li></ul>
* one\n\n*two
<ul><li>one</li></ul><p>*two</p>
* one\n** two
<ul><li>one<ul><li>two</li></ul></li></ul>
* one\n** two\n*** three\n* four
<ul><li>one<ul><li>two<ul><li>three</li></ul></li></ul></li><li>four</li></ul>
* one\n** two\n*** three\n* four\n** five\n* six
<ul><li>one<ul><li>two<ul><li>three</li></ul></li></ul></li><li>four<ul><li>five</li></ul></li><li>six</li></ul>
* one\n* two\n** one and two\n** two and three\n* three
<ul><li>one</li><li>two<ul><li>one and two</li><li>two and three</li></ul></li><li>three</li></ul>
* one and *\n* two and * more
<ul><li>one and *</li><li>two and * more</li></ul>
Foo::Bar
Foo::Bar
!WikiLink
WikiLink
!foo
!foo
file:///home/foo/tutorial.pdf
file:///home/foo/tutorial.pdf
named entities: &gt;
named entities: &gt;
garbage: &
garbage: &amp;
numbered entity: &#123;
numbered entity: &#123;
numbered hex entity: &#x123;
numbered hex entity: &#x123;
named entity: &copy;
named entity: &copy;
quoted named entity: &amp;copy;
quoted named entity: &amp;copy;
EOT

run_tests();

test_page(update_page('entity', 'quoted named entity: &amp;copy;'),
	  'quoted named entity: &amp;copy;');

# links and other attributes containing attributes

%Smilies = ('HAHA!' => '/pics/haha.png',
	    '&lt;3' => '/pics/heart.png',
	    ':"\(' => '/pics/cat.png');

%Test = split('\n',<<'EOT');
HAHA!
//img[@class="smiley"][@src="/pics/haha.png"][@alt="HAHA!"]
i <3 you
//img[@class="smiley"][@src="/pics/heart.png"][@alt="<3"]
:"(
//img[@class="smiley"][@src="/pics/cat.png"][@alt=':"(']
WikiWord
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=WikiWord"][text()="?"]
WikiWord:
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=WikiWord"][text()="?"]/following-sibling::text()[string()=":"]
OddMuse
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=OddMuse"][text()="?"]
OddMuse:
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=OddMuse"][text()="?"]/following-sibling::text()[string()=":"]
OddMuse:test
//a[@class="inter OddMuse"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?test"]/span[@class="site"][text()="OddMuse"]/following-sibling::text()[string()=":"]/following-sibling::span[@class="page"][text()="test"]
OddMuse:test: or not
//a[@class="inter OddMuse"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?test"]/span[@class="site"][text()="OddMuse"]/following-sibling::text()[string()=":"]/following-sibling::span[@class="page"][text()="test"]
OddMuse:test, and foo
//a[@class="inter OddMuse"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?test"]/span[@class="site"][text()="OddMuse"]/following-sibling::text()[string()=":"]/following-sibling::span[@class="page"][text()="test"]
PlanetMath:ZipfsLaw, and foo
//a[@class="inter PlanetMath"][@href="http://planetmath.org/encyclopedia/ZipfsLaw.html"]/span[@class="site"][text()="PlanetMath"]/following-sibling::text()[string()=":"]/following-sibling::span[@class="page"][text()="ZipfsLaw"]
[OddMuse:test]
//a[@class="inter OddMuse number"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?test"]/span/span[@class="bracket"][text()="["]/following-sibling::text()[string()="1"]/following-sibling::span[@class="bracket"][text()="]"]
![[Free Link]]
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=Free_Link"][text()="?"]
http://www.emacswiki.org
//a[@class="url http"][@href="http://www.emacswiki.org"][text()="http://www.emacswiki.org"]
<http://www.emacswiki.org>
//text()[string()="<"]/following-sibling::a[@class="url http"][@href="http://www.emacswiki.org"][text()="http://www.emacswiki.org"]/following-sibling::text()[string()=">"]
http://www.emacswiki.org/
//a[@class="url http"][@href="http://www.emacswiki.org/"][text()="http://www.emacswiki.org/"]
http://www.emacswiki.org.
//a[@class="url http"][@href="http://www.emacswiki.org"][text()="http://www.emacswiki.org"]/following-sibling::text()[string()="."]
http://www.emacswiki.org,
//a[@class="url http"][@href="http://www.emacswiki.org"][text()="http://www.emacswiki.org"]/following-sibling::text()[string()=","]
http://www.emacswiki.org;
//a[@class="url http"][@href="http://www.emacswiki.org"][text()="http://www.emacswiki.org"]/following-sibling::text()[string()=";"]
http://www.emacswiki.org:
//a[@class="url http"][@href="http://www.emacswiki.org"][text()="http://www.emacswiki.org"]/following-sibling::text()[string()=":"]
http://www.emacswiki.org?
//a[@class="url http"][@href="http://www.emacswiki.org"][text()="http://www.emacswiki.org"]/following-sibling::text()[string()="?"]
http://www.emacswiki.org/?
//a[@class="url http"][@href="http://www.emacswiki.org/"][text()="http://www.emacswiki.org/"]/following-sibling::text()[string()="?"]
http://www.emacswiki.org!
//a[@class="url http"][@href="http://www.emacswiki.org"][text()="http://www.emacswiki.org"]/following-sibling::text()[string()="!"]
http://www.emacswiki.org'
//a[@class="url http"][@href="http://www.emacswiki.org"][text()="http://www.emacswiki.org"]/following-sibling::text()[string()="'"]
http://www.emacswiki.org"
//a[@class="url http"][@href="http://www.emacswiki.org"][text()="http://www.emacswiki.org"]/following-sibling::text()[string()='"']
http://www.emacswiki.org!
//a[@class="url http"][@href="http://www.emacswiki.org"][text()="http://www.emacswiki.org"]/following-sibling::text()[string()="!"]
http://www.emacswiki.org(
//a[@class="url http"][@href="http://www.emacswiki.org"][text()="http://www.emacswiki.org"]/following-sibling::text()[string()="("]
http://www.emacswiki.org)
//a[@class="url http"][@href="http://www.emacswiki.org"][text()="http://www.emacswiki.org"]/following-sibling::text()[string()=")"]
http://www.emacswiki.org&
//a[@class="url http"][@href="http://www.emacswiki.org"][text()="http://www.emacswiki.org"]/following-sibling::text()[string()="&"]
http://www.emacswiki.org#
//a[@class="url http"][@href="http://www.emacswiki.org"][text()="http://www.emacswiki.org"]/following-sibling::text()[string()="#"]
http://www.emacswiki.org%
//a[@class="url http"][@href="http://www.emacswiki.org"][text()="http://www.emacswiki.org"]/following-sibling::text()[string()="%"]
[http://www.emacswiki.org]
//a[@class="url http number"][@href="http://www.emacswiki.org"]/span/span[@class="bracket"][text()="["]/following-sibling::text()[string()="1"]/following-sibling::span[@class="bracket"][text()="]"]
[http://www.emacswiki.org] and [http://www.emacswiki.org]
//a[@class="url http number"][@href="http://www.emacswiki.org"]/span/span[@class="bracket"][text()="["]/following-sibling::text()[string()="1"]/following-sibling::span[@class="bracket"][text()="]"]/../../following-sibling::text()[string()=" and "]/following-sibling::a[@class="url http number"][@href="http://www.emacswiki.org"]/span/span[@class="bracket"][text()="["]/following-sibling::text()[string()="2"]/following-sibling::span[@class="bracket"][text()="]"]
[http://www.emacswiki.org],
//a[@class="url http number"][@href="http://www.emacswiki.org"]/span/span[@class="bracket"][text()="["]/following-sibling::text()[string()="1"]/following-sibling::span[@class="bracket"][text()="]"]
[http://www.emacswiki.org and a label]
//a[@class="url http outside"][@href="http://www.emacswiki.org"][text()="and a label"]
[file://home/foo/tutorial.pdf local link]
//a[@class="url file outside"][@href="file://home/foo/tutorial.pdf"][text()="local link"]
file://home/foo/tutorial.pdf
//a[@class="url file"][@href="file://home/foo/tutorial.pdf"][text()="file://home/foo/tutorial.pdf"]
mailto:alex@emacswiki.org
//a[@class="url mailto"][@href="mailto:alex@emacswiki.org"][text()="mailto:alex@emacswiki.org"]
EOT

xpath_run_tests();

$NetworkFile = 0;

# --------------------

usemod_module:
print '[usemod module]';

clear_pages();

do 'modules/usemod.pl';
InitVariables();

%Test = split('\n',<<'EOT');
* ''one\n** two
<ul><li><em>one</em><ul><li>two</li></ul></li></ul>
# one\n# two
<ol><li>one</li><li>two</li></ol>
* one\n# two
<ul><li>one</li></ul><ol><li>two</li></ol>
# one\n\n#two
<ol><li>one</li></ol><p>#two</p>
# one\n# two\n## one and two\n## two and three\n# three
<ol><li>one</li><li>two<ol><li>one and two</li><li>two and three</li></ol></li><li>three</li></ol>
# one and #\n# two and # more
<ol><li>one and #</li><li>two and # more</li></ol>
: one\n: two\n:: one and two\n:: two and three\n: three
<dl class="quote"><dt /><dd>one</dd><dt /><dd>two<dl class="quote"><dt /><dd>one and two</dd><dt /><dd>two and three</dd></dl></dd><dt /><dd>three</dd></dl>
: one and :)\n: two and :) more
<dl class="quote"><dt /><dd>one and :)</dd><dt /><dd>two and :) more</dd></dl>
: one\n\n:two
<dl class="quote"><dt /><dd>one</dd></dl><p>:two</p>
; one:eins\n;two:zwei
<dl><dt>one</dt><dd>eins ;two:zwei</dd></dl>
; one:eins\n\n; two:zwei
<dl><dt>one</dt><dd>eins</dd><dt>two</dt><dd>zwei</dd></dl>
; a: b: c\n;; x: y: z
<dl><dt>a</dt><dd>b: c<dl><dt>x</dt><dd>y: z</dd></dl></dd></dl>
* foo <b>bold\n* bar </b>
<ul><li>foo <b>bold</b></li><li>bar &lt;/b&gt;</li></ul>
This is ''emphasized''.
This is <em>emphasized</em>.
This is '''strong'''.
This is <strong>strong</strong>.
This is ''longer emphasized'' text.
This is <em>longer emphasized</em> text.
This is '''longer strong''' text.
This is <strong>longer strong</strong> text.
This is '''''emphasized and bold''''' text.
This is <strong><em>emphasized and bold</em></strong> text.
This is ''emphasized '''and bold''''' text.
This is <em>emphasized <strong>and bold</strong></em> text.
This is '''bold ''and emphasized''''' text.
This is <strong>bold <em>and emphasized</em></strong> text.
This is ''emphasized text containing '''longer strong''' text''.
This is <em>emphasized text containing <strong>longer strong</strong> text</em>.
This is '''strong text containing ''emph'' text'''.
This is <strong>strong text containing <em>emph</em> text</strong>.
||one||
<table class="user"><tr><td>one</td></tr></table>
||one|| 
<table class="user"><tr><td>one</td><td align="left"> </td></tr></table>
|| one ''two'' ||
<table class="user"><tr><td align="center">one <em>two</em></td></tr></table>
|| one two ||
<table class="user"><tr><td align="center">one two </td></tr></table>
introduction\n\n||one||two||three||\n||||one two||three||
introduction<table class="user"><tr><td>one</td><td>two</td><td>three</td></tr><tr><td colspan="2">one two</td><td>three</td></tr></table>
||one||two||three||\n||||one two||three||\n\nfooter
<table class="user"><tr><td>one</td><td>two</td><td>three</td></tr><tr><td colspan="2">one two</td><td>three</td></tr></table><p>footer</p>
||one||two||three||\n||||one two||three||\n\nfooter
<table class="user"><tr><td>one</td><td>two</td><td>three</td></tr><tr><td colspan="2">one two</td><td>three</td></tr></table><p>footer</p>
|| one|| two|| three||\n|||| one two|| three||\n\nfooter
<table class="user"><tr><td align="right">one</td><td align="right">two</td><td align="right">three</td></tr><tr><td colspan="2" align="right">one two</td><td align="right">three</td></tr></table><p>footer</p>
||one ||two ||three ||\n||||one two ||three ||\n\nfooter
<table class="user"><tr><td align="left">one </td><td align="left">two </td><td align="left">three </td></tr><tr><td colspan="2" align="left">one two </td><td align="left">three </td></tr></table><p>footer</p>
|| one || two || three ||\n|||| one two || three ||\n\nfooter
<table class="user"><tr><td align="center">one </td><td align="center">two </td><td align="center">three </td></tr><tr><td colspan="2" align="center">one two </td><td align="center">three </td></tr></table><p>footer</p>
introduction\n\n||one||two||three||\n||||one two||three||\n\nfooter
introduction<table class="user"><tr><td>one</td><td>two</td><td>three</td></tr><tr><td colspan="2">one two</td><td>three</td></tr></table><p>footer</p>
 source
<pre> source</pre>
 source\n etc\n
<pre> source\n etc</pre>
 source\n \n etc\n
<pre> source\n \n etc</pre>
 source\n \n etc\n\nother
<pre> source\n \n etc</pre><p>other</p>
= title =
<h2>title</h2>
==title=
<h2>title</h2>
========fnord=
<h6>fnord</h6>
== nada\nnada ==
== nada nada ==
 == nada ==
<pre> == nada ==</pre>
==[[Free Link]]==
<h2>[[Free Link]]</h2>
EOT

run_tests();

remove_rule(\&UsemodRule);

# --------------------

usemod_options:
print '[usemod options]';

# some patterns use options in regular expressions with /o and need to be recompiled
do 'modules/usemod.pl';
$UseModSpaceRequired = 0;
$UseModMarkupInTitles = 1;
InitVariables();

%Test = split('\n',<<'EOT');
*one\n**two
<ul><li>one<ul><li>two</li></ul></li></ul>
#one\n##two
<ol><li>one<ol><li>two</li></ol></li></ol>
:one\n:two\n::one and two\n::two and three\n:three
<dl class="quote"><dt /><dd>one</dd><dt /><dd>two<dl class="quote"><dt /><dd>one and two</dd><dt /><dd>two and three</dd></dl></dd><dt /><dd>three</dd></dl>
;one:eins\n;two:zwei
<dl><dt>one</dt><dd>eins</dd><dt>two</dt><dd>zwei</dd></dl>
=='''title'''==
<h2><strong>title</strong></h2>
1 \+ 1 = 2
1 \+ 1 = 2
EOT

run_tests();


%Test = split('\n',<<'EOT');
==[[Free Link]]==
//h2/text()[string()="[Free Link]"]/following-sibling::a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=Free_Link"][text()="?"]
EOT

xpath_run_tests();

$UseModSpaceRequired = 1;
$UseModMarkupInTitles = 0;
remove_rule(\&UsemodRule);

# --------------------

markup_module:
print '[markup module]';

do 'modules/usemod.pl';
do 'modules/markup.pl';
InitVariables();

%Test = split('\n',<<'EOT');
foo
foo
/foo/
<i>foo</i>
5km/h or 6km/h
5km/h or 6km/h
/foo/ bar
<i>foo</i> bar
/foo bar 5/
<i>foo bar 5</i>
6/22/2004
6/22/2004
#!/bin/sh
#!/bin/sh
put it in ~/elisp/
put it in ~/elisp/
see /usr/bin/
see /usr/bin/
to /usr/local/share/perl/!
to /usr/local/share/perl/!
we shall laugh/cry/run around naked
we shall laugh/cry/run around naked
da *foo*
da <b>foo</b>
da *foo bar 6*
da <b>foo bar 6</b>
_foo_
<em style="text-decoration: underline; font-style: normal;">foo</em>
foo_bar_baz
foo_bar_baz
_foo bar 4_
<em style="text-decoration: underline; font-style: normal;">foo bar 4</em>
this -> that
this &#x2192; that
and this...
and this&#x2026;
foo---bar
foo&#x2014;bar
foo -- bar
foo &#x2013; bar
foo\n----\nbar
foo <hr /><p>bar</p>
foo ##bar+## baz
foo <code>bar+</code> baz
foo %%bar+%% baz
foo <span>bar+</span> baz
##http://www.example.com##
<code>http://www.example.com</code>
%%http://www.example.com%%
<span>http://www.example.com</span>
and **this\nis!** me
and <b>this\nis!</b> me
and //this\nis!// me
and <i>this\nis!</i> me
and __this\nis!__ me
and <em style="text-decoration: underline; font-style: normal;">this\nis!</em> me
and ~~this\nis!~~ me
and <em>this\nis!</em> me
um\n{{{\ncode\n}}} here
um <pre>code\n</pre><p>here</p>
um\n{{{\ncode\n}}}\n here
um <pre>code\n</pre><pre> here</pre>
um\n{{{\ncode\n}}} 	  \n here
um <pre>code\n</pre><pre> here</pre>
um\n{{{\ncode\n\nmore code\n}}} here
um <pre>code\n\nmore code\n</pre><p>here</p>
um {{{code}}} here
um {{{code}}} here
or //this// and\n//that//
or <i>this</i> and <i>that</i>
__ and 7000 chars xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
__ and 7000 chars xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
______
______
____ and __
____ and __
//// and //
//// and //
i think //the paragraph should be the limit\n\nright?//
i think //the paragraph should be the limit<p>right?//</p>
'hi'
&#x2018;hi&#x2019;
say 'hi' to mom
say &#x2018;hi&#x2019; to mom
say 'hi!' to mom
say &#x2018;hi!&#x2019; to mom
i'm tired
i&#x2019;m tired
"hi"
&#x201c;hi&#x201d;
say "hi" to mom
say &#x201c;hi&#x201d; to mom
say "hi!" to mom
say &#x201c;hi!&#x201d; to mom
i"m tired
i"m tired
He said, "[w]hen I voice complaints..."
He said, &#x201c;[w]hen I voice complaints&#x2026;&#x201d;
EOT

run_tests();

$MarkupQuotes = 0;
test_match(q{"Get lost!", they say, and I answer: "I'm not 'lost'!"},
	  q{"Get lost!", they say, and I answer: "I'm not 'lost'!"});
$MarkupQuotes = 1;
test_match(q{"Get lost!", they say, and I answer: "I'm not 'lost'!"},
	  q{&#x201c;Get lost!&#x201d;, they say, and I answer: &#x201c;I&#x2019;m not &#x2018;lost&#x2019;!&#x201d;});
$MarkupQuotes = 2;
test_match(q{"Get lost!", they say, and I answer: "I'm not 'lost'!"},
	  q{&#x00ab;Get lost!&#x00bb;, they say, and I answer: &#x00ab;I&#x2019;m not &#x2039;lost&#x203a;!&#x00bb;});
$MarkupQuotes = 3;
test_match(q{"Get lost!", they say, and I answer: "I'm not 'lost'!"},
	  q{&#x00bb;Get lost!&#x00ab;, they say, and I answer: &#x00bb;I&#x2019;m not &#x203a;lost&#x2039;!&#x00ab;});
$MarkupQuotes = 4;
test_match(q{"Get lost!", they say, and I answer: "I'm not 'lost'!"},
	  q{&#x201e;Get lost!&#x201c;, they say, and I answer: &#x201e;I&#x2019;m not &#x201a;lost&#x2018;!&#x201c;});

remove_rule(\&UsemodRule);
remove_rule(\&MarkupRule);

# --------------------

setext_module:
print '[setext module]';

clear_pages(); # link-all will confuse us
do 'modules/setext.pl';
do 'modules/link-all.pl';

%Test = split('\n',<<'EOT');
foo
foo
~foo~
<i>foo</i>
da *foo*
da *foo*
da **foo** bar
da <b>foo</b> bar
da `_**foo**_` bar
da **foo** bar
_foo_
<em style="text-decoration: underline; font-style: normal;">foo</em>
foo_bar_baz
foo_bar_baz
_foo_bar_ baz
<em style="text-decoration: underline; font-style: normal;">foo bar</em> baz
and\nfoo\n===\n\nmore\n
and <h2>foo</h2><p>more</p>
and\n\nfoo\n===\n\nmore\n
and<h2>foo</h2><p>more</p>
and\nfoo  \n--- \n\nmore\n
and <h3>foo</h3><p>more</p>
and\nfoo\n---\n\nmore\n
and <h3>foo</h3><p>more</p>
EOT

run_tests();

*GetGotoBar = *OldLinkAllGetGotoBar;
remove_rule(\&SeTextRule);
remove_rule(\&LinkAllRule);

# --------------------

anchors_module:
print '[anchors module]';

do 'modules/anchors.pl';
do 'modules/link-all.pl'; # check compatibility

%Test = split('\n',<<'EOT');
This is a [:day for fun and laughter].
//a[@class="anchor"][@name="day_for_fun_and_laughter"]
[[#day for fun and laughter]].
//a[@class="local anchor"][@href="#day_for_fun_and_laughter"][text()="day for fun and laughter"]
[[2004-08-17#day for fun and laughter]].
//a[@class="local anchor"][@href="http://localhost/test.pl/2004-08-17#day_for_fun_and_laughter"][text()="2004-08-17#day for fun and laughter"]
[[[#day for fun and laughter]]].
//text()[string()="["]/following-sibling::a[@class="local anchor"][@href="#day_for_fun_and_laughter"][text()="day for fun and laughter"]/following-sibling::text()[string()="]."]
[[[2004-08-17#day for fun and laughter]]].
//a[@class="local anchor number"][@title="2004-08-17#day_for_fun_and_laughter"][@href="http://localhost/test.pl/2004-08-17#day_for_fun_and_laughter"]/span/span[@class="bracket"][text()="["]/following-sibling::text()[string()="1"]/following-sibling::span[@class="bracket"][text()="]"]
EOT

xpath_run_tests();

$BracketWiki = 0;

%Test = split('\n',<<'EOT');
[[#day for fun and laughter|boo]].
[[#day for fun and laughter|boo]].
[[2004-08-17#day for fun and laughter|boo]].
[[2004-08-17#day for fun and laughter|boo]].
EOT

run_tests();

$BracketWiki = 1;

%Test = split('\n',<<'EOT');
[[2004-08-17#day for fun and laughter|boo]].
//a[@class="local anchor"][@href="http://localhost/test.pl/2004-08-17#day_for_fun_and_laughter"][text()="boo"]
EOT

xpath_run_tests();

$BracketWiki = 0;
remove_rule(\&AnchorsRule);
remove_rule(\&LinkAllRule);

# --------------------

link_all_module:
print '[link-all module]';

clear_pages();

add_module('link-all.pl');

update_page('foo', 'link-all for bar');

xpath_test(get_page('action=browse define=1 id=foo'),
	  '//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/wiki.pl?action=edit;id=bar"][text()="bar"]');

%Test = split('\n',<<'EOT');
testing foo.
//a[@class="local"][@href="http://localhost/test.pl/foo"][text()="foo"]
EOT

xpath_run_tests();

*GetGotoBar = *OldLinkAllGetGotoBar;
remove_rule(\&LinkAllRule);
remove_module('link-all.pl');

# --------------------

images:
print '[image module]';

do "modules/image.pl";

clear_pages();

update_page('bar', 'foo');
update_page('InterMap', " Oddmuse http://www.emacswiki.org/cgi-bin/oddmuse.pl?\n",
	    'required', 0, 1);

%Test = split('\n',<<'EOT');
EOT
xpath_run_tests();

%Test = split('\n',<<'EOT');
[[image:foo]]
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=foo;upload=1"][text()="?"]
[[image:bar]]
//a[@class="image"][@href="http://localhost/test.pl/bar"]/img[@class="upload"][@src="http://localhost/test.pl/download/bar"][@alt="bar"]
[[image:bar|alternative text]]
//a[@class="image"][@href="http://localhost/test.pl/bar"]/img[@class="upload"][@src="http://localhost/test.pl/download/bar"][@alt="alternative text"]
[[image:bar|alternative text|foo]]
//a[@class="image"][@href="http://localhost/test.pl/foo"]/img[@class="upload"][@title="alternative text"][@src="http://localhost/test.pl/download/bar"][@alt="alternative text"]
[[image/left:bar|alternative text|foo]]
//a[@class="image left"][@href="http://localhost/test.pl/foo"]/img[@class="upload"][@title="alternative text"][@src="http://localhost/test.pl/download/bar"][@alt="alternative text"]
[[image:http://example.org/wiki?a=1&b=2]]
//a[@class="image outside"][@href="http://example.org/wiki?a=1&b=2"]/img[@class="upload"][@title=""][@src="http://example.org/wiki?a=1&b=2"][@alt=""]
[[image/left/small:bar|alternative text]]
//a[@class="image left small"][@href="http://localhost/test.pl/bar"]/img[@class="upload"][@title="alternative text"][@src="http://localhost/test.pl/download/bar"][@alt="alternative text"]
[[image:http://example.org/wiki?a=1&b=2|foo|http://example.org/wiki?a=4&b=3]]
//a[@class="image outside"][@href="http://example.org/wiki?a=4&b=3"]/img[@class="upload"][@title="foo"][@src="http://example.org/wiki?a=1&b=2"][@alt="foo"]
[[image/right:bar|alternative text]]
//a[@class="image right"][@href="http://localhost/test.pl/bar"]/img[@class="upload"][@title="alternative text"][@src="http://localhost/test.pl/download/bar"][@alt="alternative text"]
[[image/left:bar|alternative text|http://www.foo.com/]]
//a[@class="image left outside"][@href="http://www.foo.com/"]/img[@class="upload"][@title="alternative text"][@src="http://localhost/test.pl/download/bar"][@alt="alternative text"]
[[image/left/small:bar|alternative text|http://www.foo.com/|more text|http://www.bar.com/]]
//a[@class="image left small outside"][@href="http://www.foo.com/"][img[@class="upload"][@title="alternative text"][@src="http://localhost/test.pl/download/bar"][@alt="alternative text"]]/following-sibling::br/following-sibling::span[@class="caption"]/a[@class="image left small outside"][@href="http://www.bar.com/"][text()="more text"]
[[image/left/small:bar|alternative text|http://www.foo.com/|more text|bar]]
//a[@class="image left small outside"][@href="http://www.foo.com/"][img[@class="upload"][@title="alternative text"][@src="http://localhost/test.pl/download/bar"][@alt="alternative text"]]/following-sibling::br/following-sibling::span[@class="caption"]/a[@class="image left small"][@href="http://localhost/test.pl/bar"][text()="more text"]
[[image:http://www.example.com/]]
//a[@class="image outside"][@href="http://www.example.com/"]/img[@class="upload"][@title=""][@src="http://www.example.com/"][@alt=""]
[[image external:foo]]
//a[@class="image"][@href="/images/foo"]/img[@class="upload"][@title=""][@src="/images/foo"][@alt=""]
[[image external:foo bar]]
//a[@class="image"][@href="/images/foo%20bar"]/img[@class="upload"][@title=""][@src="/images/foo%20bar"][@alt=""]
[[image external:foo|moo]]
//a[@class="image"][@href="/images/foo"]/img[@class="upload"][@title="moo"][@src="/images/foo"][@alt="moo"]
[[image external:foo|moo||the caption]]
//div[@class="image"]/a[@class="image"][@href="/images/foo"][img[@class="upload"][@title="moo"][@src="/images/foo"][@alt="moo"]]/following-sibling::br/following-sibling::span[@class="caption"][text()="the caption"]
[[image:foo/bar|moo||the caption]]
//div[@class="image"]/a[@class="image"][@href="/images/foo/bar"][img[@class="upload"][@title="moo"][@src="/images/foo/bar"][@alt="moo"]]/following-sibling::br/following-sibling::span[@class="caption"][text()="the caption"]
[[image:foo/bar|moo|baz|the caption]]
//div[@class="image"]/a[@class="image"][@href="http://localhost/test.pl/baz"][img[@class="upload"][@title="moo"][@src="/images/foo/bar"][@alt="moo"]]/following-sibling::br/following-sibling::span[@class="caption"][text()="the caption"]
[[image:Oddmuse:foo/bar|moo|Oddmuse:baz/zz|the caption]]
//div[@class="image"]/a[@class="image inter Oddmuse"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?baz/zz"][img[@class="upload"][@title="moo"][@src="http://www.emacswiki.org/cgi-bin/oddmuse.pl?foo/bar"][@alt="moo"]]/following-sibling::br/following-sibling::span[@class="caption"][text()="the caption"]
[[image:Oddmuse:foo/bar|moo|Oddmuse:baz/zz|the caption|Oddmuse:quux]]
//div[@class="image"]/a[@class="image inter Oddmuse"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?baz/zz"][img[@class="upload"][@title="moo"][@src="http://www.emacswiki.org/cgi-bin/oddmuse.pl?foo/bar"][@alt="moo"]]/following-sibling::br/following-sibling::span[@class="caption"][a[@class="image inter Oddmuse"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?quux"][text()="the caption"]]
[[image:Oddmuse:the foo|moo|Oddmuse:the baz|the caption|Oddmuse:the quux]]
//div[@class="image"]/a[@class="image inter Oddmuse"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?the%20baz"][img[@class="upload"][@title="moo"][@src="http://www.emacswiki.org/cgi-bin/oddmuse.pl?the%20foo"][@alt="moo"]]/following-sibling::br/following-sibling::span[@class="caption"][a[@class="image inter Oddmuse"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?the%20quux"][text()="the caption"]]
[[image:Oddmuse:Alex Schröder]]
//div/a[@class="image inter Oddmuse"][@href="http://www.emacswiki.org/cgi-bin/oddmuse.pl?Alex%20Schr%c3%b6der"][img[@class="upload"][@src="http://www.emacswiki.org/cgi-bin/oddmuse.pl?Alex%20Schr%c3%b6der"]]
EOT

xpath_run_tests();

remove_rule(\&ImageSupportRule);

# --------------------

subscriberc:
print '[subscriberc module]'; # test together with link-all module

add_module('subscriberc.pl');

%Test = split('\n',<<'EOT');
My subscribed pages: AlexSchroeder.
<a href="http://localhost/test.pl?action=rc;rcfilteronly=^(AlexSchroeder)$">My subscribed pages: AlexSchroeder</a>.
My subscribed pages: AlexSchroeder, [[LionKimbro]], [[Foo bar]].
<a href="http://localhost/test.pl?action=rc;rcfilteronly=^(AlexSchroeder|LionKimbro|Foo_bar)$">My subscribed pages: AlexSchroeder, LionKimbro, Foo bar</a>.
My subscribed categories: CategoryDecisionMaking, CategoryBar.
<a href="http://localhost/test.pl?action=rc;rcfilteronly=(CategoryDecisionMaking|CategoryBar)">My subscribed categories: CategoryDecisionMaking, CategoryBar</a>.
My subscribed pages: AlexSchroeder, [[LionKimbro]], [[Foo bar]], categories: CategoryDecisionMaking.
<a href="http://localhost/test.pl?action=rc;rcfilteronly=^(AlexSchroeder|LionKimbro|Foo_bar)$|(CategoryDecisionMaking)">My subscribed pages: AlexSchroeder, LionKimbro, Foo bar, categories: CategoryDecisionMaking</a>.
EOT

run_tests();

remove_rule(\&SubscribedRecentChangesRule);

# --------------------

toc_module:
print '[toc module]';

clear_pages();
add_module('toc.pl');
add_module('usemod.pl');
InitVariables();

%Test = split('\n',<<'EOT');
== make honey ==\n\nMoo.\n
<h2 id="toc1">make honey</h2><p>Moo.</p>
EOT

run_tests();

test_page(update_page('toc', "bla\n"
		      . "=one=\n"
		      . "blarg\n"
		      . "==two==\n"
		      . "bla\n"
		      . "==two==\n"
		      . "mu."),
	  quotemeta('<ol><li><a href="#toc1">one</a><ol><li><a href="#toc2">two</a></li><li><a href="#toc3">two</a></li></ol></li></ol>'),
	  quotemeta('<h2 id="toc1">one</h2>'),
	  quotemeta('<h2 id="toc2">two</h2>'),
	  quotemeta('bla </p><div class="toc"><h2>Contents</h2><ol><li><a '),
	  quotemeta('two</a></li></ol></li></ol></div><h2 id="toc1">one</h2>'),);

test_page(update_page('toc', "bla\n"
		      . "==two=\n"
		      . "bla\n"
		      . "===three==\n"
		      . "bla\n"
		      . "==two==\n"),
	  quotemeta('<ol><li><a href="#toc1">two</a><ol><li><a href="#toc2">three</a></li></ol></li><li><a href="#toc3">two</a></li></ol>'),
	  quotemeta('<h2 id="toc1">two</h2>'),
	  quotemeta('<h3 id="toc2">three</h3>'));

test_page(update_page('toc', "bla\n"
		      . "<toc>\n"
		      . "murks\n"
		      . "==two=\n"
		      . "bla\n"
		      . "===three==\n"
		      . "bla\n"
		      . "=one=\n"),
	  quotemeta('<ol><li><a href="#toc1">two</a><ol><li><a href="#toc2">three</a></li></ol></li><li><a href="#toc3">one</a></li></ol>'),
	  quotemeta('<h2 id="toc1">two</h2>'),
	  quotemeta('<h2 id="toc3">one</h2>'),
	  quotemeta('bla </p><div class="toc"><h2>Contents</h2><ol><li><a '),
	  quotemeta('one</a></li></ol></div><p> murks'),);

test_page(update_page('toc', "bla\n"
		      . "=one=\n"
		      . "blarg\n"
		      . "==two==\n"
		      . "<nowiki>bla\n"
		      . "==two==\n"
		      . "mu.</nowiki>\n"
		      . "<nowiki>bla\n"
		      . "==two==\n"
		      . "mu.</nowiki>\n"
		      . "yadda <code>bla\n"
		      . "==two==\n"
		      . "mu.</code>\n"
		      . "yadda <pre> has no effect! \n"
		      . "##bla\n"
		      . "==three==\n"
		      . "mu.##\n"
		      . "=one=\n"
		      . "blarg </pre>\n"),
	  quotemeta('<ol><li><a href="#toc1">one</a><ol><li><a href="#toc2">two</a></li><li><a href="#toc3">three</a></li></ol></li><li><a href="#toc4">one</a></li></ol>'),
	  quotemeta('<h2 id="toc1">one</h2>'),
	  quotemeta('<h2 id="toc2">two</h2>'),
	  quotemeta('<h2 id="toc3">three</h2>'),
	  quotemeta('<h2 id="toc4">one</h2>'),);

add_module('markup.pl');

test_page(update_page('toc', "bla\n"
		      . "=one=\n"
		      . "blarg\n"
		      . "<code>bla\n"
		      . "=two=\n"
		      . "mu.</code>\n"
		      . "##bla\n"
		      . "=three=\n"
		      . "mu.##\n"
		      . "=four=\n"
		      . "blarg\n"),
	  quotemeta('<ol><li><a href="#toc1">one</a></li><li><a href="#toc2">four</a></li></ol>'),
	  quotemeta('<h2 id="toc1">one</h2>'),
	  quotemeta('<h2 id="toc2">four</h2>'),);

remove_rule(\&UsemodRule);
remove_rule(\&MarkupRule);
remove_rule(\&TocRule);

# --------------------

comments:
print '[comments]';

clear_pages();

AppendStringToFile($ConfigFile, "\$CommentsPrefix = 'Comments on ';\n");

get_page('title=Yadda', 'aftertext=This%20is%20my%20comment.', 'username=Alex');
test_page(get_page('Yadda'), 'Describe the new page');

get_page('title=Comments_on_Yadda', 'aftertext=This%20is%20my%20comment.', 'username=Alex');
test_page(get_page('Comments_on_Yadda'), 'This is my comment\.', '-- Alex');

get_page('title=Comments_on_Yadda', 'aftertext=This%20is%20another%20comment.',
	 'username=Alex', 'homepage=http%3a%2f%2fwww%2eoddmuse%2eorg%2f');
xpath_test(get_page('Comments_on_Yadda'),
	   '//p[contains(text(),"This is my comment.")]',
	   '//a[@class="url http outside"][@href="http://www.oddmuse.org/"][text()="Alex"]');

# --------------------

headers:
print '[headers in various modules]';

clear_pages();

# without portrait-support

# nothing
update_page('headers', "== no header ==\n\ntext\n");
test_page(get_page('headers'), '== no header ==');

# usemod only
add_module('usemod.pl');
update_page('headers', "== is header ==\n\ntext\n");
test_page(get_page('headers'), '<h2>is header</h2>');

# toc + usemod only
add_module('toc.pl');
update_page('headers', "== one ==\ntext\n== two ==\ntext\n== three ==\ntext\n");
test_page(get_page('headers'),
	  '<li><a href="#headers1">one</a></li>',
	  '<li><a href="#headers2">two</a></li>',
	  '<h2 id="headers1">one</h2>',
	  '<h2 id="headers2">two</h2>', );
remove_module('usemod.pl');
remove_rule(\&UsemodRule);

# toc + headers
add_module('headers.pl');
update_page('headers', "one\n===\ntext\ntwo\n---\ntext\nthree\n====\ntext\n");
test_page(get_page('headers'),
	  '<li><a href="#headers1">one</a>',
	  '<ol><li><a href="#headers2">two</a></li></ol>',
	  '<li><a href="#headers3">three</a></li>',
	  '<h2 id="headers1">one</h2>',
	  '<h3 id="headers2">two</h3>',
	  '<h2 id="headers3">three</h2>', );
remove_module('toc.pl');
remove_rule(\&TocRule);

# headers only
update_page('headers', "is header\n=========\n\ntext\n");
test_page(get_page('headers'), '<h2>is header</h2>');
remove_module('headers.pl');
remove_rule(\&HeadersRule);

# --------------------

with_portrait_support:
print '[with portrait support]';

clear_pages();
add_module('portrait-support.pl');

# nothing
update_page('headers', "[new]foo\n== no header ==\n\ntext\n");
test_page(get_page('headers'), '<div class="color one level0"><p>foo == no header ==</p><p>text</p></div>');

# usemod only
add_module('usemod.pl');
update_page('headers', "[new]foo\n== is header ==\n\ntext\n");
test_page(get_page('headers'), '<div class="color one level0"><p>foo </p></div><h2>is header</h2>');

# usemod + toc only
add_module('toc.pl');
update_page('headers', "[new]foo\n== one ==\ntext\n== two ==\ntext\n== three ==\ntext\n");
test_page(get_page('headers'),
	  '<div class="content browse"><div class="color one level0"><p>foo </p></div>', # default to before the header
	  '<div class="toc"><h2>Contents</h2><ol>',
	  '<li><a href="#headers1">one</a></li>',
	  '<li><a href="#headers2">two</a></li>',
	  '<li><a href="#headers3">three</a></li></ol></div>',
	  '<h2 id="headers1">one</h2><p>text </p>',
	  '<h2 id="headers2">two</h2>', );
remove_module('toc.pl');
remove_rule(\&TocRule);
remove_module('usemod.pl');
remove_rule(\&UsemodRule);

# headers only
add_module('headers.pl');
update_page('headers', "[new]foo\nis header\n=========\n\ntext\n");
test_page(get_page('headers'), '<div class="color one level0"><p>foo </p></div><h2>is header</h2>');
remove_module('headers.pl');
remove_rule(\&HeadersRule);

# portrait-support, toc, and usemod

add_module('usemod.pl');
add_module('toc.pl');
update_page('headers', "[new]foo\n== one ==\ntext\n== two ==\ntext\n== three ==\ntext\n");
test_page(get_page('headers'),
	  '<li><a href="#headers1">one</a></li>',
	  '<li><a href="#headers2">two</a></li>',
	  '<div class="color one level0"><p>foo </p></div>',
	  '<h2 id="headers1">one</h2>',
	  '<h2 id="headers2">two</h2>', );

%Test = split('\n',<<'EOT');
[new]\nfoo
<div class="color one level0"><p> foo</p></div>
:[new]\nfoo
<div class="color two level1"><p> foo</p></div>
::[new]\nfoo
<div class="color one level2"><p> foo</p></div>
EOT

run_tests();

remove_rule(\&UsemodRule);
remove_rule(\&TocRule);
*GetHeader = *OldTocGetHeader;
remove_rule(\&PortraitSupportRule);
*ApplyRules = *OldPortraitSupportApplyRules;

# --------------------

hr:
print '[hr in various modules]';

clear_pages();

# without portrait-support

# nothing
update_page('hr', "one\n----\ntwo\n");
test_page(get_page('hr'), 'one ---- two');

# usemod only
add_module('usemod.pl');
update_page('hr', "one\n----\nthree\n");
test_page(get_page('hr'), '<div class="content browse"><p>one </p><hr /><p>three</p></div>');
remove_rule(\&UsemodRule);

# headers only
add_module('headers.pl');
update_page('hr', "one\n----\ntwo\n");
test_page(get_page('hr'), '<div class="content browse"><h3>one</h3><p>two</p></div>');

update_page('hr', "one\n\n----\nthree\n");
test_page(get_page('hr'), '<div class="content browse"><p>one</p><hr /><p>three</p></div>');
remove_rule(\&HeadersRule);

# --------------------

print '[with portrait support]';

clear_pages();
add_module('portrait-support.pl');


# just portrait-support
update_page('hr', "[new]one\n----\ntwo\n");
test_page(get_page('hr'), '<div class="content browse"><div class="color one level0"><p>one </p></div><hr /><p>two</p></div>');

# usemod and portrait-support
add_module('usemod.pl');
update_page('hr', "one\n----\nthree\n");
test_page(get_page('hr'), '<div class="content browse"><p>one </p><hr /><p>three</p></div>');
unlink('/tmp/oddmuse/modules/usemod.pl') or die "Cannot unlink: $!";
remove_rule(\&UsemodRule);

# headers and portrait-support
add_module('headers.pl');
update_page('hr', "one\n----\ntwo\n");
test_page(get_page('hr'), '<div class="content browse"><h3>one</h3><p>two</p></div>');

update_page('hr', "one\n\n----\nthree\n");
test_page(get_page('hr'), '<div class="content browse"><p>one</p><hr /><p>three</p></div>');
unlink('/tmp/oddmuse/modules/headers.pl') or die "Cannot unlink: $!";
remove_rule(\&HeadersRule);

remove_rule(\&PortraitSupportRule);
*ApplyRules = *OldPortraitSupportApplyRules;


# --------------------

calendar:
print '[calendar]';

clear_pages();

my ($sec, $min, $hour, $mday, $mon, $year) = localtime($Now);
$mon++;
$year += 1900;
my $year_next = $year +1;
my $year_prev = $year -1;
my $today = sprintf("%d-%02d-%02d", $year, $mon, $mday);
$oday = $mday -1;
$oday += 2 if $oday < 1;
my $otherday = sprintf("%d-%02d-%02d", $year, $mon, $oday);

add_module('calendar.pl');
xpath_test(get_page('action=calendar'),
	   # yearly navigation
	  '//div[@class="content cal year"]/p[@class="nav"]/a[@href="http://localhost/wiki.pl?action=calendar;year=' . $year_prev . '"][text()="Previous"]/following-sibling::text()[string()=" | "]/following-sibling::a[@href="http://localhost/wiki.pl?action=calendar;year=' . $year_next . '"][text()="Next"]',
	   # monthly collection
	  '//div[@class="cal month"]/pre/span[@class="title"]/a[@class="local collection month"][@href="http://localhost/wiki.pl?action=collect;match=%5e' . sprintf("%d-%02d", $year, $mon)  . '"]',
	  # today day edit
	  '//a[@class="edit today"][@href="http://localhost/wiki.pl?action=edit;id=' . $today . '"][normalize-space(text())="' . $mday . '"]',
	  # other day edit
	  '//a[@class="edit"][@href="http://localhost/wiki.pl?action=edit;id=' . $otherday . '"][normalize-space(text())="' . $oday . '"]',
	  );

update_page($today, "yadda");

xpath_test(get_page('action=calendar'),
	   # day exact match
	   '//a[@class="local exact today"][@href="http://localhost/wiki.pl/' . $today . '"][normalize-space(text())="' . $mday . '"]');

update_page("${today}_more", "more yadda");

xpath_test(get_page('action=calendar'),
	  # today exact match
	  '//a[@class="local collection today"][@href="http://localhost/wiki.pl?action=collect;match=%5e' . $today . '"][normalize-space(text())="' . $mday . '"]');

remove_rule(\&CalendarRule);
*GetHeader = *OldCalendarGetHeader;

# --------------------

crumbs:
print '[crumbs]';

clear_pages();
AppendStringToFile($ConfigFile, "\$PageCluster = 'Cluster';\n");

add_module('crumbs.pl');

update_page("HomePage", "Has to do with [[Software]].");
update_page("Software", "[[HomePage]]\n\nCheck out [[Games]].");
update_page("Games", "[[Software]]\n\nThis is it.");
xpath_test(get_page('Games'),
		'//p/span[@class="crumbs"]/a[@class="local"][@href="http://localhost/wiki.pl/HomePage"][text()="HomePage"]/following-sibling::text()[string()=" "]/following-sibling::a[@class="local"][@href="http://localhost/wiki.pl/Software"][text()="Software"]');

remove_rule(\&CrumbsRule);

# --------------------

long_table:
print '[long table]';

clear_pages();

add_module('tables-long.pl');

%Test = split('\n',<<'EOT');
<table a,b>\na=a\nb=b\na=one\nb=two
<table class="user long"><tr><th>a</th><th>b</th></tr><tr><td>one</td><td>two</td></tr></table>
<table a,b>\na=a\nb=b\na=one\nb=two\n----
<table class="user long"><tr><th>a</th><th>b</th></tr><tr><td>one</td><td>two</td></tr></table>
<table a,b>\na=a\nb=b\na=one\nb=two\n----\n\nDone.
<table class="user long"><tr><th>a</th><th>b</th></tr><tr><td>one</td><td>two</td></tr></table><p>Done.</p>
Here is a table:\n<table a,b>\na=a\nb=b\na=one\ntwo\nand a half\nb=three\na=foo\nb=bar\n----\n\nDone.\n<table foo,bar>\nfoo=test\nbar=test as well\nfoo=what we test\n----\nthe end.
Here is a table: <table class="user long"><tr><th>a</th><th>b</th></tr><tr><td>one two and a half</td><td>three</td></tr><tr><td>foo</td><td>bar</td></tr></table><p>Done. </p><table class="user long"><tr><th>test</th><th>test as well</th></tr><tr><td colspan="2">what we test</td></tr></table><p>the end.</p>
<table a,b>\na=a\nb=b\na=one\nb/2=odd\na=three
<table class="user long"><tr><th>a</th><th>b</th></tr><tr><td>one</td><td rowspan="2">odd</td></tr><tr><td>three</td></tr></table>
<table a,b,c>\na=a\nb=b\nc=c\na=one\nb/2=odd\nc=two\na=three\nc=four
<table class="user long"><tr><th>a</th><th>b</th><th>c</th></tr><tr><td>one</td><td rowspan="2">odd</td><td>two</td></tr><tr><td>three</td><td>four</td></tr></table>
<table a,b,c>\na=a\nb=b\nc=c\na=one\nb=two\nc/2=numbers\na=three\n
<table class="user long"><tr><th>a</th><th>b</th><th>c</th></tr><tr><td>one</td><td>two</td><td rowspan="2">numbers</td></tr><tr><td colspan="2">three</td></tr></table>
<table a, b, c>\na:0\nb:1\nc:00\n----\n
<table class="user long"><tr><th>0</th><th>1</th><th>00</th></tr></table>
EOT

run_tests();

remove_rule(\&TablesLongRule);

# --------------------

tags:
print '[tags]';

clear_pages();

add_module('tags.pl');

%Test = split('\n',<<'EOT');
[[tag:foo bar]]
//a[@class="outside tag"][@title="Tag"][@href="http://technorati.com/tag/foo%20bar"][@rel="tag"][text()="foo bar"]
[[tag:foo bar|mu muh!]]
//a[@class="outside tag"][@title="Tag"][@href="http://technorati.com/tag/foo%20bar"][@rel="tag"][text()="mu muh!"]
EOT

xpath_run_tests();

remove_rule(\&TagsRule);

# --------------------

moin:
print '[moin]';

clear_pages();

add_module('moin.pl');

%Test = split('\n',<<'EOT');
foo[[BR]]bar
//text()[string()="foo"]/following-sibling::br/following-sibling::text()[string()="bar"]
''foo''
//em[text()="foo"]
'''bar'''
//strong[text()="bar"]
[[foo bar]]
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=foo_bar"][text()="?"]
["foo bar"]
//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/test.pl?action=edit;id=foo_bar"][text()="?"]
* one\n* two\n** two.one
//ul/li[text()="one"]/following-sibling::li/text()[string()="two"]/following-sibling::ul/li[text()="two.one"]
 * one\n * two\n  * two.one
//ul/li[text()="one"]/following-sibling::li/text()[string()="two"]/following-sibling::ul/li[text()="two.one"]
  * one\n    * one.one\n  * two
//ul/li/text()[string()="one"]/following-sibling::ul/li[text()="one.one"]/../../following-sibling::li[text()="two"]
  * one\n    * one.one\n * two
//ul/li/text()[string()="one"]/following-sibling::ul/li[text()="one.one"]/../../following-sibling::li[text()="two"]
 1. one\n 1. two\n  1. two.one
//ol/li[text()="one"]/following-sibling::li/text()[string()="two"]/following-sibling::ol/li[text()="two.one"]
   one\n     one.one\n  two
//dl[@class="quote"]/dd/text()[normalize-space(string())="one"]/following-sibling::dl/dd[normalize-space(text())="one.one"]/../../following-sibling::dd[text()="two"]
 * one\n more\n * two\n more
//ul/li[normalize-space(text())="one more"]/following-sibling::li[normalize-space(text())="two more"]
 * one\n more\n  * two\n  more
//ul/li/text()[normalize-space(string())="one more"]/following-sibling::ul/li[normalize-space(text())="two more"]
  one\n  more\n    two\n    more
//dl[@class="quote"]/dd/text()[normalize-space(string())="one more"]/following-sibling::dl/dd[normalize-space(text())="two more"]
{{{\n[[foo bar]]\n}}}
//pre[@class="real"][text()="[[foo bar]]\n"]
EOT

xpath_run_tests();

remove_rule(\&MoinRule);

# --------------------

sidebar:
print '[sidebar]';

clear_pages();

add_module('sidebar.pl');

test_page(update_page('SideBar', 'mu'), '<div class="sidebar"><p>mu</p></div>');
test_page(get_page('HomePage'), '<div class="sidebar"><p>mu</p></div>');

print '[with toc]';

add_module('toc.pl');
add_module('usemod.pl');

AppendStringToFile($ConfigFile, "\$TocAutomatic = 0;\n");

update_page('SideBar', "bla\n\n"
	    . "== mu ==\n\n"
	    . "bla");

test_page(update_page('test', "bla\n"
		      . "<toc>\n"
		      . "murks\n"
		      . "==two=\n"
		      . "bla\n"
		      . "===three==\n"
		      . "bla\n"
		      . "=one=\n"),
	  quotemeta('<ol><li><a href="#test1">two</a><ol><li><a href="#test2">three</a></li></ol></li><li><a href="#test3">one</a></li></ol>'),
	  quotemeta('<h2 id="SideBar1">mu</h2>'),
	  quotemeta('<h2 id="test1">two</h2>'),
	  quotemeta('<h2 id="test3">one</h2>'),
	  quotemeta('bla </p><div class="toc"><h2>Contents</h2><ol><li><a '),
	  quotemeta('one</a></li></ol></div><p> murks'));

update_page('SideBar', "<toc>");
test_page(update_page('test', "bla\n"
		      . "murks\n"
		      . "==two=\n"
		      . "bla\n"
		      . "===three==\n"
		      . "bla\n"
		      . "=one=\n"),
	  quotemeta('<ol><li><a href="#test1">two</a><ol><li><a href="#test2">three</a></li></ol></li><li><a href="#test3">one</a></li></ol>'),
	  quotemeta('<h2 id="test1">two</h2>'),
	  quotemeta('<h2 id="test3">one</h2>'),
	  quotemeta('<div class="sidebar"><div class="toc"><h2>Contents</h2><ol><li><a '),
	  quotemeta('one</a></li></ol></div></div><div class="content browse"><p>'));

remove_rule(\&TocRule);
remove_rule(\&UsemodRule);

print '[with forms]'; # + pagelock + forms

add_module('forms.pl');

test_page(update_page('SideBar', '<form><h1>mu</h1></form>'), '<div class="sidebar"><p>&lt;form&gt;&lt;h1&gt;mu&lt;/h1&gt;&lt;/form&gt;</p></div>');
xpath_test(get_page('action=pagelock id=SideBar set=1 pwd=foo'), '//p/text()[string()="Lock for "]/following-sibling::a[@href="http://localhost/wiki.pl/SideBar"][@class="local"][text()="SideBar"]/following-sibling::text()[string()=" created."]');
test_page(get_page('SideBar'), '<div class="sidebar"><form><h1>mu</h1></form></div>');
# While rendering the SideBar as part of the HomePage, it should still
# be considered "locked", and therefore the form should render
# correctly.
test_page(get_page('HomePage'), '<div class="sidebar"><form><h1>mu</h1></form></div>');
# test_page(get_page('HomePage'), '<div class="sidebar"><p>&lt;form&gt;&lt;h1&gt;mu&lt;/h1&gt;&lt;/form&gt;</p></div>');
get_page('action=pagelock id=SideBar set=0 pwd=foo');

remove_rule(\&FormsRule);

*GetHeader = *OldSideBarGetHeader;

# --------------------

localnames:
print '[localnames]';

clear_pages();
use Cwd;
$dir = cwd;
$uri = "file://$dir";

add_module('localnames.pl');

xpath_test(update_page('LocalNames', "* [http://www.oddmuse.org/ OddMuse]\n"
		       . "* [[ln:$uri/ln.txt]]\n"
		       . "* [[ln:$uri/ln.txt Lion's Namespace]]\n"),
	   '//ul/li/a[@class="url http outside"][@href="http://www.oddmuse.org/"][text()="OddMuse"]',
	   '//ul/li/a[@class="url outside ln"][@href="' . $uri . '/ln.txt"][text()="' . $uri . '/ln.txt"]',
	   '//ul/li/a[@class="url outside ln"][@href="' . $uri . '/ln.txt"][text()="Lion\'s Namespace"]');

InitVariables();

%Test = split('\n',<<'EOT');
[http://www.oddmuse.org/ OddMuse]
//a[@class="url http outside"][@href="http://www.oddmuse.org/"][text()="OddMuse"]
OddMuse
//a[@class="near"][@title="LocalNames"][@href="http://www.oddmuse.org/"][text()="OddMuse"]
EOT

xpath_run_tests();

# now check whether the integration with InitVariables works
xpath_test(update_page('LocalNamesTest', 'OddMuse [[my blog]]'),
	   '//a[@class="near"][@title="LocalNames"][@href="http://www.oddmuse.org/"][text()="OddMuse"]',
	   '//a[@class="near"][@title="LocalNames"][@href="http://lion.taoriver.net/"][text()="my blog"]');

# verify that automatic update is off by default
xpath_test(update_page('LocalNamesTest', 'This is an [http://www.example.org/ Example].'),
	   '//a[@class="url http outside"][@href="http://www.example.org/"][text()="Example"]');
negative_xpath_test(get_page('LocalNames'),
		    '//ul/li/a[@class="url http outside"][@href="http://www.example.org/"][text()="Example"]');

# check automatic update
AppendStringToFile($ConfigFile, "\$LocalNamesCollect = 1;\n");

xpath_test(update_page('LocalNamesTest', 'This is an [http://www.example.com/ Example].'),
	   '//a[@class="url http outside"][@href="http://www.example.com/"][text()="Example"]');
xpath_test(get_page('LocalNames'),
	   '//ul/li/a[@class="url http outside"][@href="http://www.example.com/"][text()="Example"]');

$LocalNamesInit = 0;
LocalNamesInit();

%Test = split('\n',<<'EOT');
OddMuse
//a[@class="near"][@title="LocalNames"][@href="http://www.oddmuse.org/"][text()="OddMuse"]
[[Example]]
//a[@class="near"][@title="LocalNames"][@href="http://www.example.com/"][text()="Example"]
EOT

xpath_run_tests();

xpath_test(get_page('action=rc days=1 showedit=1'),
	   '//a[@class="local"][text()="LocalNames"]/following-sibling::strong[text()="Local names defined on LocalNamesTest: Example"]');

# more definitions on one page
update_page('LocalNamesTest', 'This is an [http://www.example.org/ Example] for [http://www.emacswiki.org EmacsWiki].');

xpath_test(get_page('action=rc days=1 showedit=1'),
	   '//a[@class="local"][text()="LocalNames"]/following-sibling::strong[text()="Local names defined on LocalNamesTest: EmacsWiki, and Example"]');

update_page('LocalNamesTest', 'This is an [http://www.example.com/ Example] for [http://www.emacswiki.org/ EmacsWiki] and [http://communitywiki.org/ Community Wiki].');

xpath_test(get_page('action=rc days=1 showedit=1'),
	   '//a[@class="local"][text()="LocalNames"]/following-sibling::strong[text()="Local names defined on LocalNamesTest: Community Wiki, EmacsWiki, and Example"]');

update_page('LocalNamesTest', 'This is [http://www.example.com/ one Example].');
xpath_test(get_page('LocalNames'),
	   '//ul/li/a[@class="url http outside"][@href="http://www.example.com/"][text()="one Example"]');

update_page('LocalNamesTest', 'This is [http://www.example.com/ one simple Example].');
negative_xpath_test(get_page('LocalNames'),
		    '//ul/li/a[@class="url http outside"][@href="http://www.example.com/"][text()="one simple Example"]');
AppendStringToFile($ConfigFile, "\$LocalNamesCollectMaxWords = 1;\n");

update_page('LocalNamesTest', 'This is [http://www.example.com/ Example one].');
negative_xpath_test(get_page('LocalNames'),
		    '//ul/li/a[@class="url http outside"][@href="http://www.example.com/"][text()="Example one"]');

*GetInterSiteUrl = *OldLocalNamesGetInterSiteUrl;

# --------------------

config_page:
print '[config page]';

clear_pages();
AppendStringToFile($ConfigFile, "\$ConfigPage = 'Config';\n");

xpath_test(update_page('Config', '@UserGotoBarPages = ("Foo", "Bar");',
		       'config', 0, 1),
	   '//div[@class="header"]/span[@class="gotobar bar"]/a[@class="local"][text()="Foo"]/following-sibling::a[@class="local"][text()="Bar"]');

# --------------------

upload:
print '[upload]';

clear_pages();
AppendStringToFile($ConfigFile, "\$UploadAllowed = 1;\n");

$page = update_page('alex pic', "#FILE image/png\niVBORw0KGgoAAAA");
test_page($page, 'This page contains an uploaded file:');
xpath_test($page, '//img[@class="upload"][@src="http://localhost/wiki.pl/download/alex_pic"][@alt="alex pic"]');
test_page_negative($page, 'AAAA');
test_page_negative(get_page('search=AAA raw=1'), 'alex_pic');
test_page(get_page('search=alex raw=1'), 'alex_pic', 'image/png');
test_page(get_page('search=png raw=1'), 'alex_pic', 'image/png');

# --------------------

include:
print '[include]';

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

# --------------------

indexed_search:
print '[indexed search]';

clear_pages();
AppendStringToFile($ConfigFile, "\$UploadAllowed = 1;\n");
add_module('search-freetext.pl');

update_page('Search (and replace)', 'Muu, or moo. [[tag:test]] [[tag:Öl]]');
update_page('To be, or not to be', 'That is the question. (Right?) [[tag:test]] [[tag:BE3]]');
update_page('alex pic', "#FILE image/png\niVBORw0KGgoAAAA");

get_page('action=buildindex pwd=foo');

test_page_negative(get_page('search=AAA raw=1'), 'alex_pic');
test_page(get_page('search=alex raw=1'), 'alex_pic', 'image/png');
test_page(get_page('search=png raw=1'), 'alex_pic', 'image/png');
get_page('action=retag id=alex_pic tags=drink%20food');
xpath_test(get_page('alex_pic'),
	   '//div[@class="tags"]/p/a[@rel="tag"]',
	   '//a[@class="outside tag"][@rel="tag"][@title="Tag"][@href="http://technorati.com/tag/drink"][text()="drink"]',
	   '//a[@class="outside tag"][@rel="tag"][@title="Tag"][@href="http://technorati.com/tag/food"][text()="food"]',
	  );
xpath_test(get_page('action=edit id=alex_pic'),
	   '//div[@class="edit tags"]/form/p/textarea[text()="drink food"]',
	  );

# index the retagging and test journal with search
get_page('action=buildindex pwd=foo');
# uses iso date regexp on page titles by default
test_page(update_page('JournalTest', '<journal search tag:drink>'),
	  '<div class="content browse"></div>');
xpath_test(update_page('JournalTest', '<journal "." search tag:drink>'),
	   '//div[@class="content browse"]/div[@class="journal"]/div[@class="page"]/h1/a[@class="local"][text()="alex pic"]',
	   '//div[@class="content browse"]/div[@class="journal"]/div[@class="page"]/p/img[@class="upload"][@alt="alex pic"][@src="http://localhost/wiki.pl/download/alex_pic"]');
xpath_test(update_page('JournalTest', '<journal "." search tag:"drink">'),
	   '//div[@class="content browse"]/div[@class="journal"]/div[@class="page"]/h1/a[@class="local"][text()="alex pic"]',
	   '//div[@class="content browse"]/div[@class="journal"]/div[@class="page"]/p/img[@class="upload"][@alt="alex pic"][@src="http://localhost/wiki.pl/download/alex_pic"]');

test_page(get_page('search=Search+replace raw=1'),
	  quotemeta('Search_(and_replace)'));
test_page(get_page('search=search raw=1'),
	  quotemeta('Search_(and_replace)'));
test_page(get_page('search=SEARCH raw=1'),
	  quotemeta('Search_(and_replace)'));
test_page(get_page('search=Search\+%5c\(and\+replace%5c\) raw=1'),
	  quotemeta('Search_(and_replace)'));
test_page(get_page('search=%22Search\+%5c\(and\+replace%5c\)%22 raw=1'),
	  quotemeta('Search_(and_replace)'));
test_page(get_page('search=moo+foo raw=1'),
	  quotemeta('Search_(and_replace)'));
test_page(get_page('search=To+be%2c+or+not+to+be raw=1'),
	  quotemeta('To_be,_or_not_to_be'));
test_page(get_page('search=%22To+be%2c+or+not+to+be%22 raw=1'),
	  quotemeta('To_be,_or_not_to_be'));
test_page(get_page('search="%22(Right%3F)%22" raw=1'),
	  quotemeta('To_be,_or_not_to_be'));
test_page(get_page('search=tag:test raw=1'),
	  quotemeta('To_be,_or_not_to_be'), quotemeta('Search_(and_replace)'));
test_page(get_page('search=tag:be3 raw=1'),
	  quotemeta('To_be,_or_not_to_be'));
test_page(get_page('search=tag:%c3%96l raw=1'),
	  quotemeta('Search_(and_replace)'));
test_page(get_page('action=cloud'),
	  'search=tag:%c3%96l', 'search=tag:test', 'search=tag:be3');

# --------------------

all:
print '[all]';

clear_pages();
add_module('all.pl');
update_page('foo', 'link to [[bar]].');
update_page('bar', 'link to [[baz]].');
test_page(get_page('action=all'), 'restricted to administrators');
xpath_test(get_page('action=all pwd=foo'),
	   '//p/a[@href="#HomePage"][text()="HomePage"]',
	   '//h1/a[@name="foo"][text()="foo"]',
	   '//a[@class="local"][@href="#bar"][text()="bar"]',
	   '//h1/a[@name="bar"][text()="bar"]',
	   '//a[@class="edit"][@title="Click to edit this page"][@href="http://localhost/wiki.pl?action=edit;id=baz"][text()="?"]',
	  );

# --------------------

irc:
print '[irc]';

clear_pages();
add_module('irc.pl');

%Test = split('\n',<<'EOT');
<kensanata> foo
<dl class="irc"><dt><b>kensanata</b></dt><dd>foo</dd></dl>
16:45 <kensanata> foo
<dl class="irc"><dt><span class="time">16:45  </span><b>kensanata</b></dt><dd>foo</dd></dl>
[16:45] <kensanata> foo
<dl class="irc"><dt><span class="time">16:45  </span><b>kensanata</b></dt><dd>foo</dd></dl>
16:45am <kensanata> foo
<dl class="irc"><dt><span class="time">16:45am  </span><b>kensanata</b></dt><dd>foo</dd></dl>
[16:45am] <kensanata> foo
<dl class="irc"><dt><span class="time">16:45am  </span><b>kensanata</b></dt><dd>foo</dd></dl>
EOT

run_tests();

remove_rule(\&IrcRule);

# --------------------

creole:
print '[creole]';

clear_pages();
add_module('creole.pl');

$BracketWiki = 1;

%Test = split('\n',<<'EOT');
# one
<ol><li>one</li></ol>
 # one
<ol><li>one</li></ol>
   #   one
<ol><li>one</li></ol>
# one\n# two
<ol><li>one</li><li>two</li></ol>
# one\n\n# two
<ol><li>one</li><li>two</li></ol>
- one
<ul><li>one</li></ul>
  - one
<ul><li>one</li></ul>
  *  one
<ul><li>one</li></ul>
# one\n- two
<ol><li>one</li></ol><ul><li>two</li></ul>
  #  one\n  - two
<ol><li>one</li></ol><ul><li>two</li></ul>
- Item 1\n- Item 2\n-- Item 2.1\n-- Item 2.2
<ul><li>Item 1</li><li>Item 2<ul><li>Item 2.1</li><li>Item 2.2</li></ul></li></ul>
* one\n** two\n*** three\n* four
<ul><li>one<ul><li>two<ul><li>three</li></ul></li></ul></li><li>four</li></ul>
this is **bold**
this is <strong>bold</strong>
**bold**
<ul><li>*bold<strong></strong></li></ul>
//italic//
<em>italic</em>
this is **//bold italic**//italic
this is <strong><em>bold italic</em></strong><em>italic</em>
//**bold italic//**bold
<em><strong>bold italic</strong></em><strong>bold</strong>
= foo
= foo
== foo
<h2>foo</h2>
=== foo
<h3>foo</h3>
==== foo
<h4>foo</h4>
===== foo
<h5>foo</h5>
====== foo
<h6>foo</h6>
======= foo
<h6>foo</h6>
== foo ==
<h2>foo</h2>
== foo = =
<h2>foo =</h2>
== foo\nbar
<h2>foo</h2><p>bar</p>
== [[foo]]
<h2>[[foo]]</h2>
foo\n\nbar
foo<p>bar</p>
foo\nbar
foo<br />bar
{{{\nfoo\n}}}
<pre class="real">foo\n</pre>
{{{\nfoo}}}
<code>\nfoo</code>
foo {{{bar}}}
foo <code>bar</code>
----
<hr />
-----  
<hr />
----\nfoo
<hr /><p>foo</p>
EOT

# Mixed lists are not supported
# - Item 1\n- Item 2\n## Item 2.1\n## Item 2.2
# <ul><li>Item 1</li><li>Item 2<ol><li>Item 2.1</li><li>Item 2.2</li></ol></li></ul>


run_tests();

update_page('link', 'test');
update_page('pic', 'test');

%Test = split('\n',<<'EOT');
[[http://www.wikicreole.org/]]
//a[@class="url http outside"][@href="http://www.wikicreole.org/"][text()="http://www.wikicreole.org/"]
http://www.wikicreole.org/
//a[@class="url http"][@href="http://www.wikicreole.org/"][text()="http://www.wikicreole.org/"]
http://www.wikicreole.org/.
//a[@class="url http"][@href="http://www.wikicreole.org/"][text()="http://www.wikicreole.org/"]
[[http://www.wikicreole.org/|Visit the WikiCreole website]]
//a[@class="url http outside"][@href="http://www.wikicreole.org/"][text()="Visit the WikiCreole website"]
[[http://www.wikicreole.org/|Visit the\nWikiCreole website]]
//a[@class="url http outside"][@href="http://www.wikicreole.org/"][text()="Visit the\nWikiCreole website"]
[[link]]
//a[text()="link"]
[[link|Go to my page]]
//a[@class="local"][@href="http://localhost/test.pl/link"][text()="Go to my page"]
[[link|Go to\nmy page]]
//a[@class="local"][@href="http://localhost/test.pl/link"][text()="Go to\nmy page"]
{{pic}}
//a[@class="image"][@href="http://localhost/test.pl/pic"][img[@class="upload"][@src="http://localhost/test.pl/download/pic"][@alt="pic"]]
{{http://example.com/}}
//a[@class="image"][@href="http://example.com/"][img[@class="url outside"][@src="http://example.com/"][@alt="http://example.com/"]]
[[link|{{pic}}]]
//a[@class="image"][@href="http://localhost/test.pl/link"][img[@class="upload"][@src="http://localhost/test.pl/download/pic"][@alt="link"]]
[[link|{{http://example.com/}}]]
//a[@class="image"][@href="http://localhost/test.pl/link"][img[@class="url outside"][@src="http://example.com/"][@alt="link"]]
[[http://example.com/|{{pic}}]]
//a[@class="image outside"][@href="http://example.com/"][img[@class="upload"][@src="http://localhost/test.pl/download/pic"][@alt="pic"]]
{{http://example.com/}}
//a[@class="image outside"][@href="http://example.com/"][img[@class="url outside"][@src="http://example.com/"]]
[[http://example.com/|{{http://mu.org/}}]]
//a[@class="image outside"][@href="http://example.com/"][img[@class="url outside"][@src="http://mu.org/"]]
EOT

xpath_run_tests();

remove_rule(\&CreoleRule);

# --------------------

end:

### END OF TESTS

print "\n";
print "$passed passed, $failed failed.\n";
