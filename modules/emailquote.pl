# Copyright (C) 2008  Weakish Jiang <weakish@gmail.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as 
# published by the Free Software Foundation.
#
# You can get a copy of GPL version 2 at
# http://www.gnu.org/licenses/gpl-2.0.html
#
# For user doc, see: 
# http://www.oddmuse.org/cgi-bin/oddmuse/Email_Quote_Extension

$ModulesDescription .= '<p>$Id: emailquote.pl,v 1.2 2008/06/25 13:21:30 weakish Exp $</p>';

push(@MyRules, \&EmailQuoteRule);

sub EmailQuoteRule {
   # > on a line with its own should work.
   if (m/\G(\s*\n)*\&gt;(\n|\Z)/cog) {
	return $q->br();
   }	
   # > hi, you mentioned that:
   # > > I don't like Oddmuse.
   # > in last letter.
   elsif ($bol && m/\G(\s*\n)*((\&gt;[ \t])+)/cog
	  or InElement('dd') && m/\G(\s*\n)+((\&gt;[ \t])+)/cog) {
    $leng = length($2)/5;
    return CloseHtmlEnvironmentUntil('dd') . OpenHtmlEnvironment('dl',$leng, 'quote')
      . $q->dt() . AddHtmlEnvironment('dd');
  }
   return undef;
}	
   

