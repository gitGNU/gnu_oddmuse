;;; oddmuse-curl.el -- edit pages on an Oddmuse wiki using curl
;; 
;; Copyright (C) 2006–2014  Alex Schroeder <alex@gnu.org>
;;           (C) 2007  rubikitch <rubikitch@ruby-lang.org>
;; 
;; Latest version:
;;   http://git.savannah.gnu.org/cgit/oddmuse.git/plain/contrib/oddmuse-curl.el
;; Discussion, feedback:
;;   http://www.emacswiki.org/cgi-bin/wiki/OddmuseCurl
;; 
;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by the Free
;; Software Foundation, either version 3 of the License, or (at your option)
;; any later version.
;; 
;; This program is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
;; FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
;; more details.
;; 
;; You should have received a copy of the GNU General Public License along
;; with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;; 
;; A simple mode to edit pages on Oddmuse wikis using Emacs and the command-line
;; HTTP client `curl'.
;; 
;; Since text formatting rules depend on the wiki you're writing for, the
;; font-locking can only be an approximation.
;; 
;; Put this file in a directory on your `load-path' and 
;; add this to your init file:
;; (require 'oddmuse)
;; (oddmuse-mode-initialize)
;; And then use M-x oddmuse-edit to start editing.

;;; Code:

(eval-when-compile
  (require 'cl)
  (require 'sgml-mode)
  (require 'skeleton))

(require 'goto-addr)
(require 'info)

(defcustom oddmuse-directory "~/.emacs.d/oddmuse"
  "Directory to store oddmuse pages."
  :type '(string)
  :group 'oddmuse)

(defcustom oddmuse-wikis
  '(("EmacsWiki" "http://www.emacswiki.org/cgi-bin/emacs"
     utf-8 "uihnscuskc" nil)
    ("OddmuseWiki" "http://www.oddmuse.org/cgi-bin/oddmuse"
     utf-8 "question" nil))
  "Alist mapping wiki names to URLs.

The elements in this list are:

NAME, the name of the wiki you provide when calling `oddmuse-edit'.

URL, the base URL of the script used when posting. If the site
uses URL rewriting, then you need to extract the URL from the
edit page. Emacs Wiki, for example, usually shows an URL such as
http://www.emacswiki.org/emacs/Foo, but when you edit the page
and examine the page source, you'll find this:

    <form method=\"post\" action=\"http://www.emacswiki.org/cgi-bin/emacs\"
          enctype=\"multipart/form-data\" accept-charset=\"utf-8\"
          class=\"edit text\">...</form>

Thus, the correct value for URL is
http://www.emacswiki.org/cgi-bin/emacs.

ENCODING, a symbol naming a coding-system.

SECRET, the secret the wiki uses if it has the Question Asker
extension enabled. If you're getting 403 responses (edit denied)
eventhough you can do it from a browser, examine your cookie in
the browser. For Emacs Wiki, for example, my cookie says:

    euihnscuskc%251e1%251eusername%251eAlexSchroeder

Use `split-string' and split by \"%251e\" and you'll see that
\"euihnscuskc\" is the odd one out. The parameter name is the
relevant string (its value is always 1).

USERNAME, your optional username to provide. It defaults to
`oddmuse-username'."
  :type '(repeat (list (string :tag "Wiki")
                       (string :tag "URL")
                       (choice :tag "Coding System"
			       (const :tag "default" utf-8)
			       (symbol :tag "specify"
				       :validate (lambda (widget)
						   (unless (coding-system-p
							    (widget-value widget))
						     (widget-put widget :error
								 "Not a valid coding system")))))
		       (choice :tag "Secret"
			       (const :tag "default" "question")
			       (string :tag "specify"))
		       (choice  :tag "Username"
				(const :tag "default" nil)
				(string :tag "specify"))))
  :group 'oddmuse)

(defcustom oddmuse-username user-full-name
  "Username to use when posting.
Setting a username is the polite thing to do."
  :type '(string)
  :group 'oddmuse)

(defcustom oddmuse-password ""
  "Password to use when posting.
You only need this if you want to edit locked pages and you
know an administrator password."
  :type '(string)
  :group 'oddmuse)

(defcustom oddmuse-use-always-minor nil
  "When t, set all the minor mode bit to all editions.
This can be changed for each edition using `oddmuse-toggle-minor'."
 :type '(boolean)
 :group 'oddmuse)

(defvar oddmuse-get-command
  "curl --silent %w\"?action=browse;raw=2;\"id=%t"
  "Command to use for publishing pages.
It must print the page to stdout.

%?  '?' character
%w  URL of the wiki as provided by `oddmuse-wikis'
%t  URL encoded pagename, eg. HowTo, How_To, or How%20To")

(defvar oddmuse-history-command
  "curl --silent %w\"?action=history;raw=1;\"id=%t"
  "Command to use for reading the history of a page.
It must print the history to stdout.

%?  '?' character
%w  URL of the wiki as provided by `oddmuse-wikis'
%t  URL encoded pagename, eg. HowTo, How_To, or How%20To")

(defvar oddmuse-rc-command
  "curl --silent %w\"?action=rc;raw=1\""
  "Command to use for Recent Changes.
It must print the RSS 3.0 text format to stdout.

%?  '?' character
%w  URL of the wiki as provided by `oddmuse-wikis'")

(defvar oddmuse-post-command
  (concat "curl --silent --write-out '%{http_code}'"
          " --form title='%t'"
          " --form summary='%s'"
          " --form username='%u'"
          " --form password='%p'"
	  " --form %q=1"
          " --form recent_edit=%m"
	  " --form oldtime=%o"
          " --form text='<-'"
          " '%w'")
  "Command to use for publishing pages.
It must accept the page on stdin.

%?  '?' character
%t  pagename
%s  summary
%u  username
%p  password
%q  question-asker cookie
%m  minor edit
%o  oldtime, a timestamp provided by Oddmuse
%w  URL of the wiki as provided by `oddmuse-wikis'")

(defvar oddmuse-link-pattern
  "\\<[[:upper:]]+[[:lower:]]+\\([[:upper:]]+[[:lower:]]*\\)+\\>"
  "The pattern used for finding WikiName.")

(defvar oddmuse-wiki nil
  "The current wiki.
Must match a key from `oddmuse-wikis'.")

(defvar oddmuse-page-name nil
  "Pagename of the current buffer.")

(defvar oddmuse-pages-hash (make-hash-table :test 'equal)
  "The wiki-name / pages pairs.")

(defvar oddmuse-index-get-command
  "curl --silent %w\"?action=index;raw=1\""
  "Command to use for publishing index pages.
It must print the page to stdout.

%?  '?' character
%w  URL of the wiki as provided by `oddmuse-wikis'
")

(defvar oddmuse-minor nil
  "Is this edit a minor change?")

(defvar oddmuse-revision nil
  "The ancestor of the current page.
This is used by Oddmuse to merge changes.")

(defun oddmuse-mode-initialize ()
  (add-to-list 'auto-mode-alist
               `(,(expand-file-name oddmuse-directory) . oddmuse-mode)))

(defun oddmuse-creole-markup ()
  "Implement markup rules for the Creole markup extension."
  (font-lock-add-keywords
   nil
  '(("^=[^=\n]+" 0 '(face info-title-1 help-echo "Creole H1")); = h1
    ("^==[^=\n]+" 0 '(face info-title-2 help-echo "Creole H2")); == h2
    ("^===[^=\n]+" 0 '(face info-title-3 help-echo "Creole H3")); === h3
    ("^====+[^=\n]+" 0 '(face info-title-4 help-echo "Creole H4")); ====h4
    ("\\_<//\\(.*\n\\)*?.*?//" 0 '(face italic help-echo "Creole italic")); //italic//
    ("\\*\\*\\(.*\n\\)*?.*?\\*\\*" 0 '(face bold help-echo "Creole bold")); **bold**
    ("__\\(.*\n\\)*?.*?__" 0 '(face underline help-echo "Creole underline")); __underline__
    ("|+=?" 0 '(face font-lock-string-face help-echo "Creole table cell"))
    ("\\\\\\\\[ \t]+" 0 '(face font-lock-warning-face help-echo "Creole line break"))
    ("^#+ " 0 '(face font-lock-constant-face help-echo "Creole ordered list"))
    ("^- " 0 '(face font-lock-constant-face help-echo "Creole ordered list")))))

(defun oddmuse-bbcode-markup ()
  "Implement markup rules for the bbcode markup extension."
  (font-lock-add-keywords
   nil
  `(("\\[b\\]\\(.*\n\\)*?.*?\\[/b\\]"
     0 '(face bold help-echo "BB code bold"))
    ("\\[i\\]\\(.*\n\\)*?.*?\\[/i\\]"
     0 '(face italic help-echo "BB code italic"))
    ("\\[u\\]\\(.*\n\\)*?.*?\\[/u\\]"
     0 '(face underline help-echo "BB code underline"))
    (,(concat "\\[url=" goto-address-url-regexp "\\]")
     0 '(face font-lock-builtin-face help-echo "BB code url"))
    ("\\[/?\\(img\\|url\\)\\]"
     0 '(face font-lock-builtin-face help-echo "BB code url or img"))
    ("\\[s\\(trike\\)?\\]\\(.*\n\\)*?.*?\\[/s\\(trike\\)?\\]"
     0 '(face strike help-echo "BB code strike"))
    ("\\[/?\\(left\\|right\\|center\\)\\]"
     0 '(face font-lock-constant-face help-echo "BB code alignment")))))

(defun oddmuse-usemod-markup ()
  "Implement markup rules for the Usemod markup extension."
  (font-lock-add-keywords
   nil
  '(("^=[^=\n]+=$"
     0 '(face info-title-1 help-echo "Usemod H1"))
    ("^==[^=\n]+==$"
     0 '(face info-title-2 help-echo "Usemod H2"))
    ("^===[^=\n]+===$"
     0 '(face info-title-3 help-echo "Usemod H3"))
    ("^====+[^=\n]+====$"
     0 '(face info-title-4 help-echo "Usemod H4"))
    ("^ .+?$"
     0 '(face font-lock-comment-face help-echo "Usemod block"))
    ("^[#]+ "
     0 '(face font-lock-constant-face help-echo "Usemod ordered list")))))

(defun oddmuse-usemod-html-markup ()
  "Implement markup rules for the HTML option in the Usemod markup extension."
  (font-lock-add-keywords
   nil
   '(("<\\(/?[a-z]+\\)" 1 '(face font-lock-function-name-face help-echo "Usemod HTML"))))
  (set (make-local-variable 'sgml-tag-alist)
       `(("b") ("code") ("em") ("i") ("strong") ("nowiki")
	 ("pre" \n) ("tt") ("u")))
  (set (make-local-variable 'skeleton-transformation) 'identity))

(defun oddmuse-extended-markup ()
  "Implement markup rules for the Markup extension."
  (font-lock-add-keywords
   nil
   '(("\\*\\w+[[:word:]-%.,:;\'\"!? ]*\\*"
      0 '(face bold help-echo "Markup bold"))
     ("\\_</\\w+[[:word:]-%.,:;\'\"!? ]*/"
      0 '(face italic help-echo "Markup italic"))
     ("_\\w+[[:word:]-%.,:;\'\"!? ]*_"
      0 '(face underline help-echo "Markup underline")))))

(defun oddmuse-basic-markup ()
  "Implement markup rules for the basic Oddmuse setup without extensions.
This function should come come last in `oddmuse-markup-functions'
because of such basic patterns as [.*] which are very generic."
  (font-lock-add-keywords
   nil
   `((,oddmuse-link-pattern
      0 '(face link help-echo "Basic wiki name"))
     ("\\[\\[.*?\\]\\]"
      0 '(face link help-echo "Basic free link"))
     (,(concat "\\[" goto-address-url-regexp "\\( .+?\\)?\\]")
      0 '(face link help-echo "Basic external free link"))
     ("^\\([*]+\\)"
      0 '(face font-lock-constant-face help-echo "Basic bullet list"))))
  (goto-address))

;; Should determine this automatically based on the version? And cache it per wiki?
;; http://emacswiki.org/wiki?action=version
(defvar oddmuse-markup-functions
  '(oddmuse-basic-markup
    oddmuse-extended-markup
    oddmuse-usemod-markup
    oddmuse-creole-markup
    oddmuse-bbcode-markup)
  "The list of functions to call when `oddmuse-mode' runs.
Later functions take precedence because they call `font-lock-add-keywords'
which adds the expressions to the front of the existing list.")

(define-derived-mode oddmuse-mode text-mode "Odd"
  "Simple mode to edit wiki pages.

Use \\[oddmuse-follow] to follow links. With prefix, allows you
to specify the target page yourself.

Use \\[oddmuse-post] to post changes. With prefix, allows you to
post the page to a different wiki.

Use \\[oddmuse-edit] to edit a different page. With prefix,
forces a reload of the page instead of just popping to the buffer
if you are already editing the page.

Customize `oddmuse-wikis' to add more wikis to the list.

Font-locking is controlled by `oddmuse-markup-functions'.

\\{oddmuse-mode-map}"
  (mapc 'funcall oddmuse-markup-functions)
  (font-lock-mode 1)
  (when buffer-file-name
    (set (make-local-variable 'oddmuse-wiki)
	 (file-name-nondirectory
	  (substring (file-name-directory buffer-file-name) 0 -1)))
    (set (make-local-variable 'oddmuse-page-name)
	 (file-name-nondirectory buffer-file-name)))
  (set (make-local-variable 'oddmuse-minor)
       oddmuse-use-always-minor)
  (set (make-local-variable 'oddmuse-revision)
       (save-excursion
	 (goto-char (point-min))
	 (if (looking-at
	      "\\([0-9]+\\) # Do not delete this line when editing!\n")
	     (prog1 (match-string 1)
	       (replace-match "")
	       (set-buffer-modified-p nil)))))
  (setq indent-tabs-mode nil))

(autoload 'sgml-tag "sgml-mode" t)

(define-key oddmuse-mode-map (kbd "C-c C-t") 'sgml-tag)
(define-key oddmuse-mode-map (kbd "C-c C-o") 'oddmuse-follow)
(define-key oddmuse-mode-map (kbd "C-c C-m") 'oddmuse-toggle-minor)
(define-key oddmuse-mode-map (kbd "C-c C-c") 'oddmuse-post)
(define-key oddmuse-mode-map (kbd "C-x C-v") 'oddmuse-revert)
(define-key oddmuse-mode-map (kbd "C-c C-f") 'oddmuse-edit)
(define-key oddmuse-mode-map (kbd "C-c C-i") 'oddmuse-insert-pagename)
(define-key oddmuse-mode-map (kbd "C-c C-h") 'oddmuse-history)
(define-key oddmuse-mode-map (kbd "C-c C-r") 'oddmuse-rc)

;; This has been stolen from simple-wiki-edit
;;;###autoload
(defun oddmuse-toggle-minor (&optional arg)
  "Toggle minor mode state."
  (interactive)
  (let ((num (prefix-numeric-value arg)))
    (cond
     ((or (not arg) (equal num 0))
      (setq oddmuse-minor (not oddmuse-minor)))
     ((> num 0) (set 'oddmuse-minor t))
     ((< num 0) (set 'oddmuse-minor nil)))
    (message "Oddmuse Minor set to %S" oddmuse-minor)
    oddmuse-minor))

(add-to-list 'minor-mode-alist
             '(oddmuse-minor " [MINOR]"))

(defun oddmuse-format-command (command)
  "Internal: Substitute oddmuse format flags according to `url',
`oddmuse-page-name', `summary', `oddmuse-username', `question',
`oddmuse-password', `oddmuse-revision'."
  (let ((hatena "?"))
    (dolist (pair '(("%w" . url)
		    ("%t" . oddmuse-page-name)
		    ("%s" . summary)
                    ("%u" . oddmuse-username)
		    ("%m" . oddmuse-minor)
                    ("%p" . oddmuse-password)
                    ("%q" . question)
		    ("%o" . oddmuse-revision)
		    ("%r" . regexp)
		    ("%\\?" . hatena)))
      (when (and (boundp (cdr pair)) (stringp (symbol-value (cdr pair))))
        (setq command (replace-regexp-in-string (car pair)
						(symbol-value (cdr pair))
                                                command t t))))
    command))

(defun oddmuse-read-wiki-and-pagename (&optional required default)
  "Read an wikiname and a pagename of `oddmuse-wikis' with completion.
If provided, REQUIRED and DEFAULT are passed along to `oddmuse-read-pagename'."
  (let ((wiki (completing-read "Wiki: " oddmuse-wikis nil t oddmuse-wiki)))
    (list wiki (oddmuse-read-pagename wiki required default))))  

;;;###autoload
(defun oddmuse-history (wiki pagename)
  "Show a page's history on a wiki using `view-mode'.
WIKI is the name of the wiki as defined in `oddmuse-wikis',
PAGENAME is the pagename of the page you want the history of.
Use a prefix argument to force a reload of the page."
  (interactive (oddmuse-read-wiki-and-pagename t oddmuse-page-name))
  (let ((name (concat wiki ":" pagename " [history]")))
    (if (and (get-buffer name)
             (not current-prefix-arg))
        (pop-to-buffer (get-buffer name))
      (let* ((wiki-data (assoc wiki oddmuse-wikis))
             (url (nth 1 wiki-data))
             (oddmuse-page-name pagename)
             (command (oddmuse-format-command oddmuse-history-command))
             (coding (nth 2 wiki-data))
             (buf (get-buffer-create name)))
        (set-buffer buf)
        (erase-buffer)
	(let ((max-mini-window-height 1))
	  (shell-command command buf))
        (pop-to-buffer buf)
	(goto-address)
	(view-mode)))))

;;;###autoload
(defun oddmuse-edit (wiki pagename)
  "Edit a page on a wiki.
WIKI is the name of the wiki as defined in `oddmuse-wikis',
PAGENAME is the pagename of the page you want to edit.
Use a prefix argument to force a reload of the page."
  (interactive (oddmuse-read-wiki-and-pagename))
  (make-directory (concat oddmuse-directory "/" wiki) t)
  (let ((name (concat wiki ":" pagename)))
    (if (and (get-buffer name)
             (not current-prefix-arg))
        (pop-to-buffer (get-buffer name))
      (let* ((wiki-data (assoc wiki oddmuse-wikis))
             (url (nth 1 wiki-data))
	     (oddmuse-page-name pagename)
             (command (oddmuse-format-command oddmuse-get-command))
             (coding (nth 2 wiki-data))
             (buf (find-file-noselect (concat oddmuse-directory "/" wiki "/"
					      pagename)))
             (coding-system-for-read coding)
             (coding-system-for-write coding))
	;; don't use let for dynamically bound variable
        (set-buffer buf)
        (unless (equal name (buffer-name)) (rename-buffer name))
        (erase-buffer)
	(let ((max-mini-window-height 1))
	  (oddmuse-run "Loading" command buf nil))
        (pop-to-buffer buf)
	(oddmuse-mode)))))

(defalias 'oddmuse-go 'oddmuse-edit)

(autoload 'word-at-point "thingatpt")

;;;###autoload
(defun oddmuse-follow (arg)
  "Figure out what page we need to visit
and call `oddmuse-edit' on it."
  (interactive "P")
  (let ((pagename (or (and arg (oddmuse-read-pagename oddmuse-wiki))
		      (oddmuse-pagename-at-point)
		      (oddmuse-read-pagename oddmuse-wiki))))
    (oddmuse-edit (or oddmuse-wiki
                      (read-from-minibuffer "URL: "))
                  pagename)))

(defun oddmuse-current-free-link-contents ()
  "Free link contents if the point is between [[ and ]]."
  (save-excursion
    (let* ((pos (point))
           (start (search-backward "[[" nil t))
           (end (search-forward "]]" nil t)))
      (and start end (>= end pos)
           (replace-regexp-in-string
            " " "_"
            (buffer-substring (+ start 2) (- end 2)))))))

(defun oddmuse-pagename-at-point ()
  "Page name at point."
  (let ((pagename (word-at-point)))
    (or (oddmuse-current-free-link-contents)
	(oddmuse-wikiname-p pagename))))

(defun oddmuse-wikiname-p (pagename)
  "Whether PAGENAME is WikiName or not."
  (when pagename
    (let (case-fold-search)
      (when (string-match (concat "^" oddmuse-link-pattern "$") pagename)
	pagename))))

;; (oddmuse-wikiname-p nil)
;; (oddmuse-wikiname-p "WikiName")
;; (oddmuse-wikiname-p "not-wikiname")
;; (oddmuse-wikiname-p "notWikiName")

(defun oddmuse-run (mesg command buf on-region)
  "Print MESG and run COMMAND on the current buffer.
MESG should be appropriate for the following uses:
  \"MESG...\"
  \"MESG...done\"
  \"MESG failed: REASON\"
Save outpout in BUF and report an appropriate error.
ON-REGION indicates whether the commands runs on the region
such as when posting, or whether it just runs by itself such
as when loading a page."
  (message "%s using %s..." mesg command)
  ;; If ON-REGION, the resulting HTTP CODE is found in BUF, so check
  ;; that, too.
  (if (and (= 0 (if on-region
		    (shell-command-on-region (point-min) (point-max) command buf)
		  (shell-command command buf)))
	   (or (not on-region)
	       (string= "302" (with-current-buffer buf
				(buffer-string)))))
      (message "%s...done" mesg)
    (let ((err "Unknown error"))
      (with-current-buffer buf
	(when (re-search-forward "<h1>\\(.*?\\)\\.?</h1>" nil t)
	  (setq err (match-string 1))))
      (error "%s...%s" mesg err))))

;;;###autoload
(defun oddmuse-post (summary)
  "Post the current buffer to the current wiki.
The current wiki is taken from `oddmuse-wiki'."
  (interactive "sSummary: ")
  ;; when using prefix or on a buffer that is not in oddmuse-mode
  (when (or (not oddmuse-wiki) current-prefix-arg)
    (set (make-local-variable 'oddmuse-wiki)
         (completing-read "Wiki: " oddmuse-wikis nil t)))
  (when (not oddmuse-page-name)
    (set (make-local-variable 'oddmuse-page-name)
         (read-from-minibuffer "Pagename: " (buffer-name))))
  (let* ((list (assoc oddmuse-wiki oddmuse-wikis))
         (url (nth 1 list))
         (oddmuse-minor (if oddmuse-minor "on" "off"))
         (coding (nth 2 list))
         (coding-system-for-read coding)
         (coding-system-for-write coding)
	 (question (nth 3 list))
	 (oddmuse-username (or (nth 4 list)
			       oddmuse-username))
         (command (oddmuse-format-command oddmuse-post-command))
	 (buf (get-buffer-create " *oddmuse-response*"))
	 (text (buffer-string)))
    (and buffer-file-name (basic-save-buffer))
    (oddmuse-run "Posting" command buf t)))

(defun oddmuse-make-completion-table (wiki)
  "Create pagename completion table for WIKI.
If available, return precomputed one."
  (or (gethash wiki oddmuse-pages-hash)
      (oddmuse-compute-pagename-completion-table wiki)))

(defun oddmuse-compute-pagename-completion-table (&optional wiki-arg)
  "Really fetch the list of pagenames from WIKI.
This command is used to reflect new pages to `oddmuse-pages-hash'."
  (interactive)
  (let* ((wiki (or wiki-arg
                   (completing-read "Wiki: " oddmuse-wikis nil t oddmuse-wiki)))
         (url (cadr (assoc wiki oddmuse-wikis)))
         (command (oddmuse-format-command oddmuse-index-get-command))
         table)
    (message "Getting index of all pages...")
    (prog1
	(setq table (split-string (shell-command-to-string command)))
      (puthash wiki table oddmuse-pages-hash)
      (message "Getting index of all pages...done"))))

(defun oddmuse-read-pagename (wiki &optional require default)
  "Read a pagename of WIKI with completion.
Optional arguments REQUIRE and DEFAULT are passed on to `completing-read'.
Typically you would use t and a `oddmuse-page-name', if that makes sense."
  (completing-read (if default
		       (concat "Pagename [" default "]: ")
		     "Pagename: ")
		   (oddmuse-make-completion-table wiki)
		   nil require nil nil default))

;;;###autoload
(defun oddmuse-rc (&optional include-minor-edits)
  "Show Recent Changes.
With universal argument, reload."
  (interactive "P")
  (let* ((wiki (or oddmuse-wiki
		   (completing-read "Wiki: " oddmuse-wikis nil t)))
	 (name (concat "*" wiki " RC*")))
    (if (and (get-buffer name)
             (not current-prefix-arg))
        (pop-to-buffer (get-buffer name))
      (let* ((wiki-data (assoc wiki oddmuse-wikis))
             (url (nth 1 wiki-data))
             (command (oddmuse-format-command oddmuse-rc-command))
             (coding (nth 2 wiki-data))
             (buf (get-buffer-create name))
             (coding-system-for-read coding)
             (coding-system-for-write coding))
	(set-buffer buf)
        (unless (equal name (buffer-name)) (rename-buffer name))
        (erase-buffer)
	(let ((max-mini-window-height 1))
	  (oddmuse-run "Load recent changes" command buf nil))
	(oddmuse-rc-buffer)
	(set (make-local-variable 'oddmuse-wiki) wiki)))))

(defun oddmuse-rc-buffer ()
  "Parse current buffer as RSS 3.0 and display it correctly."
  (let (result)
    (dolist (item (cdr (split-string (buffer-string) "\n\n")));; skip first item
      (let ((data (mapcar (lambda (line)
			    (when (string-match "^\\(.*?\\): \\(.*\\)" line)
			      (cons (match-string 1 line)
				    (match-string 2 line))))
			  (split-string item "\n"))))
	(setq result (cons data result))))
    (erase-buffer)
    (dolist (item (nreverse result))
      (insert "[[" (cdr (assoc "title" item)) "]] – "
	      (cdr (assoc "generator" item)) "\n"))
    (goto-char (point-min))
    (oddmuse-mode)))

;;;###autoload
(defun oddmuse-revert ()
  "Revert this oddmuse page."
  (interactive)
  (let ((current-prefix-arg 4))
    (oddmuse-edit oddmuse-wiki oddmuse-page-name)))

;;;###autoload
(defun oddmuse-insert-pagename (pagename)
  "Insert a PAGENAME of current wiki with completion."
  (interactive (list (oddmuse-read-pagename oddmuse-wiki)))
  (insert pagename))

;;;###autoload
(defun emacswiki-post (&optional pagename summary)
  "Post the current buffer to the EmacsWiki.
If this command is invoked interactively: with prefix argument,
prompts for pagename, otherwise set pagename as basename of
`buffer-file-name'.

This command is intended to post current EmacsLisp program easily."
  (interactive)
  (let* ((oddmuse-wiki "EmacsWiki")
         (oddmuse-page-name (or pagename
                                (and (not current-prefix-arg)
                                     buffer-file-name
                                     (file-name-nondirectory buffer-file-name))
                                (oddmuse-read-pagename oddmuse-wiki)))
         (summary (or summary (read-string "Summary: "))))
    (oddmuse-post summary)))

(defun oddmuse-url (wiki pagename)
  "Get the URL of oddmuse wiki."
  (condition-case v
      (concat (or (cadr (assoc wiki oddmuse-wikis)) (error)) "/" pagename)
    (error nil)))

;;;###autoload
(defun oddmuse-browse-page (wiki pagename)
  "Ask a WWW browser to load an Oddmuse page.
WIKI is the name of the wiki as defined in `oddmuse-wikis',
PAGENAME is the pagename of the page you want to browse."
  (interactive (oddmuse-read-wiki-and-pagename))
  (browse-url (oddmuse-url wiki pagename)))

;;;###autoload
(defun oddmuse-browse-this-page ()
  "Ask a WWW browser to load current oddmuse page."
  (interactive)
  (oddmuse-browse-page oddmuse-wiki oddmuse-page-name))

;;;###autoload
(defun oddmuse-kill-url ()
  "Make the URL of current oddmuse page the latest kill in the kill ring."
  (interactive)
  (kill-new (oddmuse-url oddmuse-wiki oddmuse-page-name)))

(provide 'oddmuse)

;;; oddmuse-curl.el ends here
