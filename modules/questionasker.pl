# Copyright (C) 2004  Brock Wilcox <awwaiid@thelackthereof.org>
# Copyright (C) 2006  Alex Schroeder <alex@gnu.org>
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

$ModulesDescription .= '<p>$Id: questionasker.pl,v 1.11 2006/06/05 21:28:14 as Exp $</p>';

use vars qw(@QuestionaskerQuestions
	    $QuestionaskerRememberAnswer
	    $QuestionaskerRequiredList
	    %QuestionaskerProtectedForms);

# A list of arrays. The first element in each array is a string, the
# question to be asked. The second element is a subroutine which is
# passed the answer as the first argument.
@QuestionaskerQuestions =
  (['What is the first letter of this question?' => sub { shift =~ /^\s*W\s*$/i }],
   ['How many letters are in the word "four"?' => sub { shift =~ /^\s*(4|four)\s*$/i }],
   ['Tell me any number between 1 and 10' => sub { shift =~ /^\s*([1-9]|10|one|two|three|four|five|six|seven|eight|nine|ten)\s*$/ }],
   ["How many lives does a cat have?" => sub { shift =~ /^\s*(9|nine)\s*$/i }],
   ["What is 2 + 4?" => sub { shift =~ /^\s*(6|six)\s*$/i }],
  );

# The page name for exceptions, if defined. Every page linked to via
# WikiWord or [[free link]] is considered to be a page which needs
# questions asked. All other pages do not require questions asked. If
# not set, then all pages need questions asked.
$QuestionaskerRequiredList = '';

# If a user answers a question correctly, remember this in the cookie
# and don't ask any further questions.
$QuestionaskerRememberAnswer = 1;

# Forms using one of the following classes are protected.
%QuestionaskerProtectedForms = ('comment' => 1,
				'edit upload' => 1,
				'edit text' => 1,);

push(@MyInitVariables, \&QuestionaskerInit);

sub QuestionaskerInit {
  $QuestionaskerRequiredList = FreeToNormal($QuestionaskerRequiredList);
  push (@AdminPages, $QuestionaskerRequiredList);
  $CookieParameters{question} = '';
  $InvisibleCookieParameters{question} = 1;
}

*OldQuestionaskerDoPost = *DoPost;
*DoPost = *NewQuestionaskerDoPost;

sub NewQuestionaskerDoPost {
  my(@params) = @_;
  my $id = FreeToNormal(GetParam('title', undef));
  my $preview = GetParam('Preview', undef); # case matters!
  my $question_num = GetParam('question_num', undef);
  my $answer = GetParam('answer', undef);
  unless (UserIsAdmin()
	  or $QuestionaskerRememberAnswer && GetParam('question', 0)
	  or $preview
	  or $QuestionaskerQuestions[$question_num][1]($answer)
	  or QuestionaskerException($id)) {
    print GetHeader('', T('Edit Denied'), undef, undef, '403 FORBIDDEN');
    print $q->p(T('You did not answer correctly.'));
    print $q->p(T('Contact the wiki administrator for more information.'));
    PrintFooter();
    # logging to the error log file of the server
    # warn "Q: '$QuestionaskerQuestions[$question_num][0]', A: '$answer'\n";
    return;
  }
  SetParam('question', 1) unless GetParam('question', 0);
  return (OldQuestionaskerDoPost(@params));
}

*OldQuestionaskerGetFormStart = *GetFormStart;
*GetFormStart = *NewQuestionaskerGetFormStart;

sub NewQuestionaskerGetFormStart {
  my ($ignore, $method, $class) = @_;
  my $form = OldQuestionaskerGetFormStart(@_);
  if ($QuestionaskerProtectedForms{$class}
      and not QuestionaskerException(GetId())
      and not $QuestionaskerRememberAnswer && GetParam('question', 0)
      and not UserIsAdmin()) {
    $form .= QuestionaskerGetQuestion();
  }
  return $form;
}

sub QuestionaskerGetQuestion {
  my $question_number = int(rand(scalar(@QuestionaskerQuestions)));
  return $q->div({-class=>'question'},
		 $q->p(T('To save this page you must answer this question:')),
		 $q->blockquote($q->p($QuestionaskerQuestions[$question_number][0]),
				$q->p($q->input({-type=>'text', -name=>'answer'}),
				      $q->input({-type=>'hidden', -name=>'question_num',
						 -value=>$question_number}))));
}

sub QuestionaskerException {
  my $id = shift;
  return 0 unless $QuestionaskerRequiredList and $id;
  my $data = GetPageContent($QuestionaskerRequiredList);
  if ($WikiLinks) {
    while ($data =~ /$LinkPattern/g) {
      return 0 if FreeToNormal($1) eq $id;
    }
  }
  if ($FreeLinks) {
    while ($data =~ /\[\[$FreeLinkPattern\]\]/g) {
      return 0 if FreeToNormal($1) eq $id;
    }
  }
  return 1;
}
