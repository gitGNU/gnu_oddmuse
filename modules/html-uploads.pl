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

use strict;
use v5.10;

AddModuleDescription('html-uploads.pl', 'Restricted HTML Upload');

our (%Action, @UploadTypes);
$Action{download} = \&HtmlUploadsDoDownload;

# anybody can download raw html

sub HtmlUploadsDoDownload {
  push(@UploadTypes, 'text/html') unless grep(/^text\/html$/, @UploadTypes);
  return DoDownload(@_);
}

# but only admins can upload raw html

*OldHtmlUploadsDoPost = \&DoPost;
*DoPost = \&NewHtmlUploadsDoPost;

sub NewHtmlUploadsDoPost {
  my @args = @_;
  if (not grep(/^text\/html$/, @UploadTypes)
      and UserIsAdmin()) {
    push(@UploadTypes, 'text/html');
  }
  return OldHtmlUploadsDoPost(@args);
}
