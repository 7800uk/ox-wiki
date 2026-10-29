;;; ox-wiki.el --- Org HTML export in MediaWiki's skins -*- lexical-binding: t; -*-

;; Author: Jacob Walchuk
;; URL: https://github.com/7800uk/ox-wiki
;; Version: 0.1.0
;; Keywords: outlines, hypermedia, wp
;; Package-Requires: ((emacs "29.1"))
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:

;; An Org export backend derived from `html' that emits the page skeleton of a
;; MediaWiki skin, so an exported Org file reads as a wiki article: content
;; column, tab row, sidebar, wiki footer.  Three skins ship with it, `vector'
;; (Vector legacy, the 2010 Vector), `monobook' and `citizen'; see SKINS.org
;; for how to add another.
;;
;; Beside the article it can write the pages the tabs point at: a read-only
;; source view of the Org text and of the LaTeX export, a PDF, and, when the
;; file is tracked by git, a revision history with MediaWiki-style diffs.  Those
;; live in ox-wiki-pages.el.
;;
;; No stylesheet here is written by hand except css/org-wiki.css.  The skins'
;; stylesheets are their own, vendored under vendor/ and rebuilt with their
;; icons inlined by tools/build-css.py.  A skin's scripts are vendored the same
;; way, rebuilt by tools/build-js.py, and run on js/mediawiki.js, a small
;; stand-in for the client runtime a wiki would provide.
;;
;; Org 9.6 or newer is wanted, which is what Emacs 29 bundles.  It is not
;; declared as a package dependency on purpose: naming `org' there makes a
;; package manager fetch and build a second Org, which is worth avoiding for a
;; version that is already in the box.
;;
;; Usage:
;;
;;   (add-to-list 'load-path "~/Development/ox-wiki")
;;   (require 'ox-wiki)
;;
;; then `C-c C-e w w' from any Org buffer.

;;; Code:

(require 'ox-html)
(require 'cl-lib)
(require 'subr-x)
(require 'json)

;; Loaded on demand by the export commands, so that rendering a page in a
;; buffer costs nothing when the companion pages are not wanted.
(declare-function org-wiki-pages-write "ox-wiki-pages" (info html-file))

(defconst org-wiki-directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory holding this file, its css/, js/ and images/.")


;;; Options

(defgroup org-wiki nil
  "Org HTML export in MediaWiki's skins."
  :tag "Org Export Wiki"
  :group 'org-export)

(defcustom org-wiki-skin 'vector
  "Skin to render pages in.  See `org-wiki-skins' for what is available.
Per file: #+WIKI_SKIN."
  :group 'org-wiki
  :type 'symbol)

(defcustom org-wiki-sitename "Orgfiles"
  "Name of the wiki, used in the search box and the footer.
Per file: #+WIKI_SITENAME."
  :group 'org-wiki
  :type 'string)

(defcustom org-wiki-tagline "From Orgfiles, exported from Org mode"
  "Text of the tagline under the page title.
MediaWiki puts \"From Wikipedia, the free encyclopedia\" here.
Per file: #+WIKI_TAGLINE."
  :group 'org-wiki
  :type 'string)

(defcustom org-wiki-type "Article"
  "What the leftmost tab says -- MediaWiki's namespace tab.
Per file: #+WIKI_TYPE."
  :group 'org-wiki
  :type 'string)

(defcustom org-wiki-logo "images/logo.svg"
  "Image to use as the wiki logo, inlined into each page.
A relative name is looked for beside the Org file first, then in this
package.  Per file: #+WIKI_LOGO."
  :group 'org-wiki
  :type 'string)

(defcustom org-wiki-logo-href "index.html"
  "Where the logo points.  Per file: #+WIKI_HOME."
  :group 'org-wiki
  :type 'string)

(defcustom org-wiki-buttons
  '(("images/poweredby_org.svg" "https://orgmode.org/" "Powered by Org mode"))
  "Images to show in the footer, as a list of (IMAGE HREF ALT).
HREF and ALT may be left out.  IMAGE is resolved like `org-wiki-logo' and
inlined, so the exported page stays self-contained.

Per file, one button per line:

  #+WIKI_BUTTONS: (\"badge.svg\" \"https://example.org/\" \"Example\")"
  :group 'org-wiki
  :type '(repeat (list (string :tag "Image")
                       (string :tag "Link")
                       (string :tag "Alt text"))))

(defcustom org-wiki-sidebar nil
  "Org file describing the sidebar, or nil for `org-wiki-default-sidebar'.

Each first-level heading becomes a portlet titled after the heading, and
each list item under it becomes a link:

  * Navigation
  - [[index.html][Main page]]
  - [[all.html][All pages]]

A relative name is resolved against the exported file's directory.
Per file: #+WIKI_SIDEBAR."
  :group 'org-wiki
  :type '(choice (const :tag "Use the built-in default" nil) file))

(defcustom org-wiki-default-sidebar
  '((:id "navigation" :label "Navigation"
     :links ((:text "Main page" :href "index.html" :id "n-mainpage" :accesskey "z")))
    (:id "tb" :label "Tools"
     :links ((:text "Printable version" :href "javascript:print();" :id "t-print"
              :accesskey "p"))))
  "Sidebar used when no sidebar file is given.
Same shape as what `org-wiki--read-sidebar' returns: a list of menu plists."
  :group 'org-wiki
  :type '(repeat plist))

(defcustom org-wiki-login nil
  "Whether to show the personal-tools menu, with its \"Log in\" link.
Off by default: an exported page has nobody to log in.  Per file:
#+WIKI_LOGIN, which is most at home in a #+SETUPFILE shared by the wiki."
  :group 'org-wiki
  :type 'boolean)

(defcustom org-wiki-login-url "#"
  "Where the \"Log in\" link points.  Per file: #+WIKI_LOGIN_URL."
  :group 'org-wiki
  :type 'string)

(defcustom org-wiki-personal-tools
  '(:id "personal" :label "Personal tools"
    :links ((:text "Not logged in" :href "#" :id "pt-anonuserpage")))
  "The personal-tools menu, at the top right.
A \"Log in\" link to `org-wiki-login-url' is added after these links.
Shown only when `org-wiki-login' is on.  Per file, the links can be given
one per line as (TEXT HREF), or as a lone nil for none but \"Log in\":

  #+WIKI_PERSONAL: nil"
  :group 'org-wiki
  :type 'plist)

(defcustom org-wiki-footer-places
  '((:text "Privacy policy" :href "#" :id "footer-places-privacy")
    (:text "About" :href "#" :id "footer-places-about")
    (:text "Disclaimers" :href "#" :id "footer-places-disclaimers"))
  "Links in the footer's link row.
Per file, one link per line, each a Lisp list of (TEXT HREF); a lone nil
leaves the row empty:

  #+WIKI_FOOTER_PLACES: (\"About\" \"about.html\")"
  :group 'org-wiki
  :type '(repeat plist))

(defcustom org-wiki-footer-notice "Generated from Org mode."
  "Attribution line in the footer, or nil for none.
The skin's own credit, its `:credit', follows it on the same line.
Per file: #+WIKI_FOOTER_NOTICE; left empty, it drops the notice."
  :group 'org-wiki
  :type '(choice (const :tag "None" nil) string))

(defcustom org-wiki-credit t
  "Whether the footer credits where the skin's design came from.
Per file: #+WIKI_CREDIT."
  :group 'org-wiki
  :type 'boolean)

(defcustom org-wiki-search nil
  "Whether to show the search box.
Off by default, like `org-wiki-login'.  Per file: #+WIKI_SEARCH_BOX, with
#+WIKI_SEARCH saying where the box posts."
  :group 'org-wiki
  :type 'boolean)

(defcustom org-wiki-search-action "https://duckduckgo.com/"
  "Form action of the search box.
The box is a plain GET form; nothing here runs a wiki search.  The default
sends the query to a web search engine so the control at least works.
Per file: #+WIKI_SEARCH."
  :group 'org-wiki
  :type 'string)

(defcustom org-wiki-search-field "q"
  "Name of the search form's text input."
  :group 'org-wiki
  :type 'string)

(defcustom org-wiki-search-fields nil
  "Extra hidden fields posted with the search form, as an alist."
  :group 'org-wiki
  :type '(alist :key-type string :value-type string))

(defcustom org-wiki-toc-title "Contents"
  "Heading of the table of contents, as MediaWiki labels it."
  :group 'org-wiki
  :type 'string)

(defcustom org-wiki-references-title "References"
  "Heading of the footnote section.
Org calls it \"Footnotes\"; MediaWiki articles call it \"References\"."
  :group 'org-wiki
  :type 'string)

(defcustom org-wiki-latex t
  "Whether to offer the LaTeX source and the PDF.
Nil drops the \"LaTeX source\" tab, the \"View PDF\" tab, and the work
behind them.  Per file: #+WIKI_LATEX."
  :group 'org-wiki
  :type 'boolean)

(defcustom org-wiki-pdf t
  "Whether to run LaTeX and write a PDF beside the exported page.
Ignored when `org-wiki-latex' is nil.  Turning this off keeps the LaTeX
source view but drops the \"View PDF\" tab.  Per file: #+WIKI_PDF."
  :group 'org-wiki
  :type 'boolean)

(defcustom org-wiki-git t
  "Whether to offer the revision history of a git-tracked file.
A file that git does not track never gets the tab, whatever this says.
Per file: #+WIKI_GIT."
  :group 'org-wiki
  :type 'boolean)

(defcustom org-wiki-history-limit 20
  "How many revisions the history page lists, and writes diff pages for.
Each revision costs up to two pages, and with `org-wiki-style-method' at its
default every page carries its own copy of the stylesheet, so a long history
is not free.  Set `org-wiki-style-method' to `link' before raising this far."
  :group 'org-wiki
  :type 'integer)

(defcustom org-wiki-output-directory nil
  "Where exported pages are written, or nil to put them beside the Org file.
A relative name is resolved against the Org file's own directory, so \"build\"
collects a whole tree's output into one place per directory.  Every page of an
export -- the article, the source views, the diffs, the PDF -- lands together,
and they refer to each other by bare file name, so the directory can be served
or moved as a unit."
  :group 'org-wiki
  :type '(choice (const :tag "Beside the Org file" nil) directory))

(defcustom org-wiki-style-method 'inline
  "How the stylesheets, and a skin's scripts, reach the exported page.

`inline' copies them into <style> and <script> elements, which makes each
page a single self-contained file.  `link' emits <link> and <script src>
elements pointing at `org-wiki-style-base-url', and you are responsible for
putting the css/ and js/ directories there."
  :group 'org-wiki
  :type '(choice (const :tag "Inline in a <style> element" inline)
                 (const :tag "Link to an external copy" link)))

(defcustom org-wiki-style-base-url "ox-wiki/"
  "URL prefix the stylesheets and scripts live under.
Used when `org-wiki-style-method' is `link'."
  :group 'org-wiki
  :type 'string)


;;; Skins

(defvar org-wiki-skins nil
  "Alist of (NAME . PLIST) for every skin that has been defined.

PLIST keys:

  :title        human-readable name
  :stylesheets  stylesheets the skin needs, named relative to the package
  :body-class   classes MediaWiki puts on <body> for this skin
  :html-class   classes the skin puts on <html>, or nil
  :credit       a sentence crediting where the skin's design came from,
                for the footer
  :scripts      scripts the skin needs, named like :stylesheets; they go
                in <head>, in order
  :modules      ResourceLoader modules to run once the page is parsed,
                which :scripts must define
  :own-toc      non-nil if the skin draws the table of contents itself,
                from the page plist's :toc, rather than having it placed
                in the article
  :page         function of one argument, the page plist built by
                `org-wiki--page', returning everything from <body> to
                </body>.

See ox-wiki-skin-vector.el for a worked example, and SKINS.org for the rest.")

(defun org-wiki-define-skin (name &rest plist)
  "Register the skin NAME, described by PLIST.  See `org-wiki-skins'."
  (setf (alist-get name org-wiki-skins) plist)
  name)

(defun org-wiki--skin-name (info)
  "Return the name of the skin INFO, the export channel, asks for."
  (let ((s (plist-get info :wiki-skin)))
    (if (stringp s) (intern (string-trim s)) (or s org-wiki-skin))))

(defun org-wiki--skin (name)
  "Return the definition of skin NAME, loading it if need be.

A skin lives in a library called `ox-wiki-skin-NAME\', anywhere on
`load-path\', whose job is to call `org-wiki-define-skin\'.  Requiring it by
name rather than hunting for files means a skin someone else wrote is
installed like any other package."
  (or (alist-get name org-wiki-skins)
      (progn (require (intern (format "ox-wiki-skin-%s" name)) nil t)
             (alist-get name org-wiki-skins))
      (error "ox-wiki: no skin `%s\' (loaded: %s)"
             name
             (if org-wiki-skins
                 (mapconcat (lambda (s) (symbol-name (car s))) org-wiki-skins ", ")
               "none"))))


;;; Small helpers

(defun org-wiki--esc (string)
  "Escape STRING for use in HTML text or an attribute value."
  (org-html-encode-plain-text (or string "")))

(defun org-wiki--attr (name value)
  "Return ` NAME=\"VALUE\"', or the empty string when VALUE is nil or empty."
  (if (or (null value) (equal value "")) ""
    (format " %s=\"%s\"" name (org-wiki--esc value))))

(defun org-wiki--untag (html)
  "Return HTML as plain text, for somewhere no markup is allowed.
Page titles are HTML, because an Org title can carry emphasis, but the
<title> element can hold neither tags nor escaped entities."
  (let ((s (replace-regexp-in-string "<[^>]*>" "" (or html ""))))
    (setq s (replace-regexp-in-string
             "&#\\([0-9]+\\);"
             (lambda (m) (string (string-to-number (match-string 1 m))))
             s))
    (dolist (pair '(("&lt;" . "<") ("&gt;" . ">") ("&quot;" . "\"")
                    ("&#39;" . "'") ("&nbsp;" . " ") ("&amp;" . "&")))
      (setq s (replace-regexp-in-string (car pair) (cdr pair) s t t)))
    s))

(defun org-wiki--slug (string)
  "Turn STRING into something usable as an identifier."
  (let ((s (replace-regexp-in-string "[^[:alnum:]]+" "-" (or string ""))))
    (downcase (replace-regexp-in-string "\\`-+\\|-+\\'" "" s))))

(defun org-wiki--flag (value)
  "Interpret VALUE, which may have come from a keyword, as a boolean."
  (if (stringp value)
      (not (member (downcase (string-trim value)) '("" "nil" "no" "off" "false")))
    (and value t)))

(defun org-wiki--read-forms (value)
  "Return VALUE as a list of Lisp forms.
A list is returned as it is; a string is read, one form after another, so
several keyword lines can accumulate into one list."
  (cond
   ((null value) nil)
   ((consp value) value)
   ((stringp value)
    (let ((start 0) (forms nil) (len (length value)))
      (condition-case nil
          (while (< start len)
            (let ((read (read-from-string value start)))
              (push (car read) forms)
              (setq start (cdr read))))
        (error nil))
      (nreverse forms)))
   (t nil)))

(defconst org-wiki--mime-types
  '(("svg" . "image/svg+xml") ("png" . "image/png") ("gif" . "image/gif")
    ("jpg" . "image/jpeg") ("jpeg" . "image/jpeg") ("webp" . "image/webp")
    ("ico" . "image/x-icon") ("pdf" . "application/pdf"))
  "Extension to media type, for the files ox-wiki inlines.")

(defun org-wiki--data-uri (file &optional mime)
  "Return FILE as a data: URI, or nil when it cannot be read.
MIME overrides the type guessed from the extension."
  (when (and file (file-readable-p file) (not (file-directory-p file)))
    (let ((type (or mime
                    (cdr (assoc (downcase (or (file-name-extension file) ""))
                                org-wiki--mime-types))
                    "application/octet-stream")))
      (concat "data:" type ";base64,"
              (base64-encode-string
               (with-temp-buffer
                 (set-buffer-multibyte nil)
                 (insert-file-contents-literally file)
                 (buffer-string))
               t)))))

(defun org-wiki--text-data-uri (string &optional mime)
  "Return STRING as a base64 data: URI of type MIME (text/plain by default)."
  (concat "data:" (or mime "text/plain") ";charset=utf-8;base64,"
          (base64-encode-string (encode-coding-string string 'utf-8) t)))

(defun org-wiki--plain (data info)
  "Return DATA, an Org secondary string, as plain text.
Falls back to interpreting the data when INFO is not a live export channel:
the companion pages are built from `org-export-get-environment' alone, which
has no `:exported-data' cache for `org-export-data' to use."
  (cond
   ((null data) "")
   ((stringp data) data)
   ((plist-get info :exported-data) (org-export-data data info))
   (t (string-trim (substring-no-properties (org-element-interpret-data data))))))

(defun org-wiki--locate (name info)
  "Find NAME, an asset named relative to the Org file or to this package.
INFO is the export communication channel.  Absolute names are returned as
they are.  Returns nil when nothing matches."
  (when (org-string-nw-p name)
    (if (file-name-absolute-p name)
        (and (file-readable-p name) name)
      (let* ((input (plist-get info :input-file))
             (here (and input (expand-file-name name (file-name-directory input))))
             (mine (expand-file-name name org-wiki-directory)))
        (cond ((and here (file-readable-p here)) here)
              ((file-readable-p mine) mine))))))


;;; Menus

;; A menu is a plist (:id ID :label LABEL :links LINKS), and each link is a
;; plist (:text TEXT :href HREF :id ID :title TITLE :accesskey KEY :selected
;; BOOL).  Skins decide how to wrap them; these two helpers are what they share.

(defun org-wiki--item (link &optional span)
  "Render LINK as a list item.  SPAN wraps the label, the way Vector does."
  (let ((label (org-wiki--esc (plist-get link :text)))
        (href (plist-get link :href)))
    (concat "<li"
            (org-wiki--attr "id" (plist-get link :id))
            (format " class=\"%smw-list-item\""
                    (if (plist-get link :selected) "selected " ""))
            ">"
            (if href
                (concat "<a"
                        (org-wiki--attr "href" href)
                        (org-wiki--attr "title" (plist-get link :title))
                        (org-wiki--attr "accesskey" (plist-get link :accesskey))
                        ">" (if span (format "<span>%s</span>" label) label) "</a>")
              (if span (format "<span>%s</span>" label) label))
            "</li>")))

(defun org-wiki--items (menu &optional span)
  "Render the links of MENU as list items.  SPAN is passed to `org-wiki--item'."
  (mapconcat (lambda (l) (concat "\t\t\t" (org-wiki--item l span) "\n"))
             (plist-get menu :links) ""))


;;; The sidebar, read from an Org file

(defun org-wiki--link-text (link)
  "Return the visible text of LINK, an Org link element."
  (let ((contents (org-element-contents link)))
    (string-trim
     (if contents
         (substring-no-properties (org-element-interpret-data contents))
       (or (org-element-property :raw-link link) "")))))

(defun org-wiki--read-sidebar (file)
  "Read FILE and return its first-level headings as a list of menu plists.
Each list item under a heading becomes a link; an item without a link
becomes plain text.  Returns nil when FILE cannot be read."
  (when (and file (file-readable-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (let ((org-inhibit-startup t))
        (delay-mode-hooks (org-mode)))
      (delq nil
            (org-element-map (org-element-parse-buffer) 'headline
              (lambda (headline)
                (when (= 1 (org-element-property :level headline))
                  (let ((label (substring-no-properties
                                (org-element-property :raw-value headline))))
                    (list :id (org-wiki--slug label)
                          :label label
                          :links (org-wiki--sidebar-links headline))))))))))

(defun org-wiki--sidebar-links (headline)
  "Return the items under HEADLINE as link plists."
  (org-element-map headline 'item
    (lambda (item)
      (let ((link (org-element-map item 'link #'identity nil t)))
        (if link
            (list :text (org-wiki--link-text link)
                  :href (org-element-property :raw-link link))
          (let ((para (org-element-map item 'paragraph #'identity nil t)))
            (when para
              (list :text (string-trim
                           (substring-no-properties
                            (org-element-interpret-data
                             (org-element-contents para)))))))))))) 


;;; Page assembly

(defun org-wiki--output-file (name)
  "Return NAME, redirected into `org-wiki-output-directory' when one is set.
Creates the directory if it is not there."
  (if (not org-wiki-output-directory)
      name
    (let ((dir (expand-file-name
                org-wiki-output-directory
                (file-name-directory (expand-file-name name)))))
      (make-directory dir t)
      (expand-file-name (file-name-nondirectory name) dir))))

(defun org-wiki--companion (file suffix)
  "Return the name of FILE's companion page for SUFFIX, e.g. \"source\"."
  (format "%s-%s.html" (file-name-base file) suffix))

(defun org-wiki--pdf-name (file)
  "Return the name of the PDF beside FILE."
  (concat (file-name-base file) ".pdf"))

(defun org-wiki--git-tracked-p (file)
  "Return non-nil when FILE is tracked by git."
  (and file (file-exists-p file) (executable-find "git")
       (let ((default-directory (file-name-directory (expand-file-name file))))
         (zerop (call-process "git" nil nil nil "ls-files" "--error-unmatch"
                              (file-name-nondirectory file))))))

(defun org-wiki-features (info)
  "Return which optional features are on for this export, as a plist.
INFO is the export communication channel.  Keys are :latex, :pdf and :git,
and each is nil or t.  The git answer also depends on whether the file is
actually tracked, and the LaTeX ones on whether a LaTeX program is around."
  (let* ((file (plist-get info :input-file))
         (latex (and (org-wiki--flag (plist-get info :wiki-latex))
                     (or (executable-find "pdflatex")
                         (executable-find "xelatex")
                         (executable-find "lualatex")
                         (executable-find "latexmk"))
                     t)))
    (list :latex latex
          :pdf (and latex (org-wiki--flag (plist-get info :wiki-pdf)) t)
          :git (and (org-wiki--flag (plist-get info :wiki-git))
                    (org-wiki--git-tracked-p file)
                    t))))

(defun org-wiki-action-tabs (info selected)
  "Return the action tabs -- MediaWiki's right-hand group -- as a menu plist.
INFO is the export channel.  SELECTED is one of `read', `source', `pdf' or
`history'; tabs whose feature is off are left out."
  (let* ((file (plist-get info :input-file))
         (base (and file (concat (file-name-base file) ".html")))
         (features (org-wiki-features info))
         (links (list (list :text "Read" :id "ca-view"
                            :href (or base "#")
                            :selected (eq selected 'read)))))
    (push (list :text "View source" :id "ca-viewsource" :accesskey "e"
                :title "This page is exported from Org; its source is read-only"
                :href (org-wiki--companion (or file "page") "source")
                :selected (eq selected 'source))
          links)
    (when (plist-get features :pdf)
      (push (list :text "View PDF" :id "ca-pdf"
                  :title "The LaTeX export of this page, as a PDF"
                  :href (org-wiki--pdf-name (or file "page"))
                  :selected (eq selected 'pdf))
            links))
    (when (plist-get features :git)
      (push (list :text "View history" :id "ca-history" :accesskey "h"
                  :title "Revisions of this page, from git"
                  :href (org-wiki--companion (or file "page") "history")
                  :selected (eq selected 'history))
            links))
    (list :id "views" :label "Views" :links (nreverse links))))

(defun org-wiki--namespace-tabs (info &optional extra selected)
  "Return the namespace tabs -- MediaWiki's left-hand group.
INFO is the export channel.  EXTRA is a list of further link plists to put
after the namespace tab, and SELECTED names the one to mark, or nil to mark
the namespace tab itself."
  (list :id "namespaces" :label "Namespaces"
        :links (cons (list :text (or (plist-get info :wiki-type) org-wiki-type)
                           :id "ca-nstab-main" :accesskey "c"
                           :href (let ((f (plist-get info :input-file)))
                                   (if f (concat (file-name-base f) ".html") "#"))
                           :selected (null selected))
                     extra)))

(defun org-wiki--logo (info)
  "Return the logo for this page as (:href H :src URI).  INFO is the channel."
  (let* ((name (or (plist-get info :wiki-logo) org-wiki-logo))
         (file (org-wiki--locate name info)))
    (list :href (or (plist-get info :wiki-logo-href) org-wiki-logo-href)
          :src (and file (org-wiki--data-uri file)))))

(defun org-wiki--buttons (info)
  "Return the footer buttons as a list of (:src :href :alt).  INFO is the channel."
  (delq nil
        (mapcar
         (lambda (spec)
           ;; A button is (IMAGE HREF ALT); a bare string is just an image, and
           ;; (IMAGE . HREF) is accepted because it is the obvious thing to write.
           (let* ((spec (if (stringp spec) (list spec) spec))
                  (image (car spec))
                  (rest (cdr spec))
                  (href (if (consp rest) (car rest) rest))
                  (alt (and (consp rest) (cadr rest)))
                  (file (org-wiki--locate image info))
                  (src (and file (org-wiki--data-uri file))))
             (when src
               (list :src src :href href
                     :alt (or alt (file-name-base image))))))
         (or (org-wiki--read-forms (plist-get info :wiki-buttons))
             org-wiki-buttons))))

(defun org-wiki--link-forms (value default)
  "Return the links VALUE, a keyword's (TEXT HREF) forms, as link plists.
A lone nil among the forms gives no links at all; no forms give DEFAULT."
  (let ((forms (org-wiki--read-forms value)))
    (if (null forms)
        default
      (delq nil (mapcar (lambda (form)
                          (and (consp form)
                               (list :text (car form) :href (cadr form))))
                        forms)))))

(defun org-wiki--modified (info)
  "Return when the file INFO exports was last changed, as a Lisp time."
  (let ((file (plist-get info :input-file)))
    (or (and file (file-exists-p file)
             (file-attribute-modification-time (file-attributes file)))
        (current-time))))

(defun org-wiki--last-edited (info)
  "Return the \"last edited\" sentence for the footer, from INFO."
  (format "This page was last edited on %s."
          (string-trim (format-time-string "%e %B %Y, at %H:%M (%Z)"
                                           (org-wiki--modified info)))))

(defun org-wiki--sidebar (info)
  "Return the sidebar menus for this export.  INFO is the channel."
  (let* ((name (or (plist-get info :wiki-sidebar) org-wiki-sidebar))
         (file (org-wiki--locate name info)))
    (or (and file (org-wiki--read-sidebar file))
        org-wiki-default-sidebar)))

(cl-defun org-wiki--page (info &key title content namespace-tabs action-tabs
                               (action "view") subtitle toc)
  "Build the page plist a skin renders.  INFO is the export channel.
TITLE and CONTENT are HTML.  NAMESPACE-TABS and ACTION-TABS are menu
plists.  ACTION becomes MediaWiki's body class, and SUBTITLE the line
under the title.  TOC is the table of contents as `org-wiki--toc-entries'
returns it, for a skin that draws its own."
  (let* ((file (plist-get info :input-file))
         (slug (org-wiki--slug (if file (file-name-base file) (or title "page"))))
         (author (org-wiki--plain (plist-get info :author) info))
         (sitename (or (plist-get info :wiki-sitename) org-wiki-sitename)))
    (list
     :skin (org-wiki--skin-name info)
     :lang (or (plist-get info :language) "en")
     :slug slug
     :action action
     :title (or title "Untitled")
     :tagline (or (plist-get info :wiki-tagline) org-wiki-tagline)
     :subtitle subtitle
     :content content
     :toc toc
     :namespace-tabs (or namespace-tabs (org-wiki--namespace-tabs info))
     :action-tabs (or action-tabs (org-wiki-action-tabs info 'read))
     :sitename sitename
     :personal (and (org-wiki--flag (plist-get info :wiki-login))
                    (org-combine-plists
                     org-wiki-personal-tools
                     (list :links
                           (append (org-wiki--link-forms
                                    (plist-get info :wiki-personal)
                                    (plist-get org-wiki-personal-tools :links))
                                   (list (list :text "Log in" :id "pt-login"
                                               :accesskey "o"
                                               :href (or (plist-get info :wiki-login-url)
                                                         org-wiki-login-url)))))))
     :sidebar (org-wiki--sidebar info)
     :logo (org-wiki--logo info)
     :search (and (org-wiki--flag (plist-get info :wiki-search))
                  (list :action (or (plist-get info :wiki-search-action)
                                    org-wiki-search-action)
                        :name org-wiki-search-field
                        :fields org-wiki-search-fields
                        :sitename sitename))
     :modified (org-wiki--modified info)
     :footer-info (delq nil
                        (list (org-wiki--last-edited info)
                              (and (org-string-nw-p author)
                                   (format "Written by %s." author))
                              (let ((notice
                                     (string-join
                                      (delq nil
                                            (list (org-string-nw-p
                                                   (or (plist-get info :wiki-footer-notice)
                                                       org-wiki-footer-notice))
                                                  (and (org-wiki--flag
                                                        (plist-get info :wiki-credit))
                                                       (plist-get (org-wiki--skin
                                                                   (org-wiki--skin-name info))
                                                                  :credit))))
                                      "  ")))
                                (and (org-string-nw-p notice) (org-wiki--esc notice)))))
     :footer-places (org-wiki--link-forms (plist-get info :wiki-footer-places)
                                          org-wiki-footer-places)
     :footer-buttons (org-wiki--buttons info)
     :head (plist-get info :wiki-head))))


;;; Stylesheets

(defun org-wiki--stylesheets (page)
  "Return the stylesheets PAGE needs, as (RELATIVE-URL . ABSOLUTE-FILE) pairs.
The skin's own come first, then the shared ones, so css/org-wiki.css has the
last word."
  (let ((skin (org-wiki--skin (plist-get page :skin))))
    (mapcar (lambda (s) (cons s (expand-file-name s org-wiki-directory)))
            (append (plist-get skin :stylesheets)
                    '("css/mediawiki-extras.css" "css/org-wiki.css")))))

(defun org-wiki--style-element (page)
  "Return the <style> or <link> elements carrying the skin for PAGE."
  (concat
   (mapconcat
    (lambda (sheet)
      (pcase org-wiki-style-method
        ('link (format "<link rel=\"stylesheet\" href=\"%s%s\">\n"
                       (org-wiki--esc org-wiki-style-base-url)
                       (org-wiki--esc (car sheet))))
        (_ (if (not (file-readable-p (cdr sheet)))
               (format "<!-- ox-wiki: missing stylesheet %s -->\n"
                       (org-wiki--esc (car sheet)))
             (concat "<style>\n"
                     (with-temp-buffer (insert-file-contents (cdr sheet))
                                       (buffer-string))
                     "\n</style>\n")))))
    (org-wiki--stylesheets page) "")
   ;; The logo is per page, so it is a rule of its own rather than something
   ;; baked into the vendored stylesheet.
   (let ((src (plist-get (plist-get page :logo) :src)))
     (when src
       (format "<style>#p-logo a.mw-wiki-logo{background-image:url(\"%s\")}</style>\n"
               src)))))

(defun org-wiki--script-element (page)
  "Return the <script> elements carrying the skin's scripts for PAGE, if any.
Scripts are inlined or linked as `org-wiki-style-method' says, like the
stylesheets, and are followed by a call to start the skin's :modules."
  (let* ((skin (org-wiki--skin (plist-get page :skin)))
         (modules (plist-get skin :modules)))
    (concat
     (mapconcat
      (lambda (name)
        (let ((file (expand-file-name name org-wiki-directory)))
          (pcase org-wiki-style-method
            ('link (format "<script src=\"%s%s\"></script>\n"
                           (org-wiki--esc org-wiki-style-base-url)
                           (org-wiki--esc name)))
            (_ (if (not (file-readable-p file))
                   (format "<!-- ox-wiki: missing script %s -->\n" (org-wiki--esc name))
                 (concat "<script>\n"
                         ;; Inline, the text must not close its own element.
                         (replace-regexp-in-string
                          "</\\(script\\)" "<\\\\/\\1"
                          (with-temp-buffer (insert-file-contents file)
                                            (buffer-string))
                          t)
                         "\n</script>\n"))))))
      (plist-get skin :scripts) "")
     (when modules
       (format "<script>mw.loader.load(%s);</script>\n" (json-encode modules))))))

(defun org-wiki--document (page)
  "Render PAGE as a complete HTML document."
  (let ((skin (org-wiki--skin (plist-get page :skin))))
    (concat
     "<!DOCTYPE html>\n"
     (format "<html class=\"client-nojs%s\" lang=\"%s\" dir=\"ltr\">\n"
             (let ((class (plist-get skin :html-class)))
               (if class (concat " " class) ""))
             (plist-get page :lang))
     "<head>\n"
     (or (plist-get page :head)
         (format "<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>%s</title>\n"
                 (org-wiki--esc (org-wiki--untag (plist-get page :title)))))
     (org-wiki--style-element page)
     (org-wiki--script-element page)
     "</head>\n"
     (funcall (plist-get skin :page) page)
     "</html>\n")))

(defun org-wiki-body-class (page)
  "Return the <body> class list for PAGE, for a skin to use."
  (let ((skin (org-wiki--skin (plist-get page :skin))))
    (format "%s mediawiki ltr sitedir-ltr mw-hide-empty-elt ns-0 ns-subject page-%s rootpage-%s action-%s"
            (plist-get skin :body-class)
            (plist-get page :slug) (plist-get page :slug)
            (plist-get page :action))))


;;; Table of contents

(defun org-wiki--toc-entry (entry)
  "Render the TOC link for ENTRY, one of `org-wiki--toc-entries'."
  (format "<a href=\"#%s\"><span class=\"tocnumber\">%s</span> <span class=\"toctext\">%s</span></a>"
          (plist-get entry :id) (plist-get entry :number) (plist-get entry :text)))

(defun org-wiki--toc-list (entries)
  "Build the nested <ul> of ENTRIES, a list of (LEVEL SECTION HTML)."
  (let* ((start-level (1- (nth 0 (car entries))))
         (prev-level start-level))
    (concat
     (mapconcat
      (lambda (entry)
        (cl-destructuring-bind (level section html) entry
          (let* ((cnt (- level prev-level))
                 (times (if (> cnt 0) (1- cnt) (- cnt))))
            (setq prev-level level)
            (concat
             (org-html--make-string
              times (if (> cnt 0) "\n<ul>\n<li>" "</li>\n</ul>\n"))
             (if (> cnt 0) "\n<ul>\n<li" "</li>\n<li")
             (format " class=\"toclevel-%d tocsection-%d\">" level section)
             html))))
      entries "\n")
     (org-html--make-string (- prev-level start-level) "</li>\n</ul>\n"))))

(defun org-wiki--toc-entries (depth info)
  "Return the headings down to DEPTH, as the table of contents lists them.
INFO is the export communication channel.  Each entry is a plist:
:level, :section (its position in the list, from 1), :number (\"2.1\"),
:id (the heading's anchor) and :text (its title, as HTML)."
  ;; MediaWiki numbers its contents whether or not the headings themselves are
  ;; numbered, so the numbering is counted here rather than read from
  ;; `:headline-numbering', which is empty under #+OPTIONS: num:nil.
  (let ((section 0)
        (counters (make-vector (1+ org-export-max-depth) 0)))
    (mapcar
     (lambda (headline)
       (let ((level (org-export-get-relative-level headline info)))
         (setq section (1+ section))
         (cl-incf (aref counters (1- level)))
         (cl-loop for i from level to org-export-max-depth
                  do (aset counters i 0))
         (list :level level :section section
               :number (mapconcat #'number-to-string
                                  (cl-loop for i from 0 below level
                                           collect (aref counters i))
                                  ".")
               :id (org-html--reference headline info)
               :text (org-export-data-with-backend
                      (org-export-get-alt-title headline info)
                      (org-export-toc-entry-backend 'wiki)
                      info))))
     (org-export-collect-headlines info depth))))

(defun org-wiki-toc (depth info)
  "Return the table of contents down to DEPTH, in MediaWiki's markup.
INFO is the export communication channel."
  (let ((entries (mapcar (lambda (e)
                           (list (plist-get e :level) (plist-get e :section)
                                 (org-wiki--toc-entry e)))
                         (org-wiki--toc-entries depth info))))
    (when entries
      (concat
       "<div id=\"toc\" class=\"toc\" role=\"navigation\" aria-labelledby=\"mw-toc-heading\">\n"
       "<input type=\"checkbox\" role=\"button\" id=\"toctogglecheckbox\""
       " class=\"toctogglecheckbox\" style=\"display:none\" />\n"
       (format "<div class=\"toctitle\" lang=\"%s\" dir=\"ltr\">" (plist-get info :language))
       (format "<h2 id=\"mw-toc-heading\">%s</h2>" (org-wiki--esc org-wiki-toc-title))
       "<span class=\"toctogglespan\">"
       "<label class=\"toctogglelabel\" for=\"toctogglecheckbox\"></label></span>"
       "</div>\n"
       (org-wiki--toc-list entries)
       "\n</div>\n"))))


;;; Transcoders

(defun org-wiki--footnotes (info)
  "Return the footnote section, headed the way a wiki heads it.
INFO is the export communication channel."
  (org-html-footnote-section
   (org-combine-plists
    info
    (list :html-footnotes-section
          (format (concat "<div id=\"footnotes\">\n<h2 class=\"footnotes\">%s</h2>\n"
                          "<div id=\"text-footnotes\">\n%%2$s\n</div>\n</div>")
                  (org-wiki--esc org-wiki-references-title))))))

(defun org-wiki--place-toc (contents toc)
  "Insert TOC into CONTENTS where MediaWiki puts it: after the lead section.
That is, immediately before the first heading.  With no heading to find --
a page whose TOC was asked for but whose sections are all below the export
depth -- the TOC goes at the top."
  (cond
   ((null toc) contents)
   ((string-match "^<div id=\"outline-container-" contents)
    (concat (substring contents 0 (match-beginning 0))
            toc
            (substring contents (match-beginning 0))))
   (t (concat toc contents))))

(defun org-wiki-inner-template (contents info)
  "Wrap CONTENTS in the parser-output div, with the TOC.  INFO is the channel.
A skin that draws its own TOC gets none here; `org-wiki-template' hands it
the entries instead."
  (let ((depth (and (not (plist-get (org-wiki--skin (org-wiki--skin-name info))
                                    :own-toc))
                    (plist-get info :with-toc))))
    (concat
     "<div class=\"mw-parser-output\">\n"
     (org-wiki--place-toc contents (and depth (org-wiki-toc depth info)))
     (org-wiki--footnotes info)
     "</div>\n")))

(defun org-wiki-template (contents info)
  "Return the whole document.  CONTENTS is the body; INFO is the channel."
  (let ((title (org-export-data (plist-get info :title) info))
        (depth (plist-get info :with-toc)))
    (org-wiki--document
     (org-wiki--page
      (org-combine-plists
       info
       (list :wiki-head (concat (org-html--build-meta-info info)
                                (org-html--build-head info)
                                (org-html--build-mathjax-config info))))
      :title (if (org-string-nw-p title) title "Untitled")
      :content contents
      :toc (and depth (org-wiki--toc-entries depth info))))))

(defun org-wiki-filter-table (output _backend _info)
  "Give the table in OUTPUT MediaWiki's `wikitable' class.
`org-html-table' ignores `:html-table-attributes' when the doctype is
HTML5, so the class is added here instead, and only when the table has
none of its own from an #+ATTR_HTML line."
  (if (string-match-p "\\`<table [^>]*class=" output)
      output
    (replace-regexp-in-string "\\`<table" "<table class=\"wikitable\"" output t t)))

(defun org-wiki-filter-link (output _backend _info)
  "Mark absolute links in OUTPUT as external, the way MediaWiki does."
  (if (and (string-match-p "\\`<a href=\"\\(?:[a-z][-+.a-z0-9]*:\\)?//" output)
           (not (string-match-p "\\`<a [^>]*class=" output)))
      (replace-regexp-in-string "\\`<a " "<a class=\"external text\" " output t t)
    output))


;;; Backend

(org-export-define-derived-backend 'wiki 'html
  :menu-entry
  '(?w "Export to Wiki HTML"
       ((?w "As HTML file" org-wiki-export-to-html)
        (?W "As HTML buffer" org-wiki-export-as-html)
        (?o "As HTML file and open"
            (lambda (a s v b)
              (if a (org-wiki-export-to-html t s v b)
                (org-open-file (org-wiki-export-to-html nil s v b)))))))
  :translate-alist
  '((template . org-wiki-template)
    (inner-template . org-wiki-inner-template))
  :filters-alist
  '((:filter-link . org-wiki-filter-link)
    (:filter-table . org-wiki-filter-table))
  :options-alist
  '((:section-numbers nil "num" nil)
    (:html-doctype "HTML_DOCTYPE" nil "html5" t)
    (:html-html5-fancy nil "html5-fancy" nil)
    (:html-head-include-default-style nil "html-style" nil)
    (:html-head-include-scripts nil "html-scripts" nil)
    (:html-checkbox-type nil nil 'html)
    (:wiki-skin "WIKI_SKIN" nil org-wiki-skin t)
    (:wiki-sitename "WIKI_SITENAME" nil org-wiki-sitename t)
    (:wiki-tagline "WIKI_TAGLINE" nil org-wiki-tagline t)
    (:wiki-type "WIKI_TYPE" nil org-wiki-type t)
    (:wiki-logo "WIKI_LOGO" nil org-wiki-logo t)
    (:wiki-logo-href "WIKI_HOME" nil org-wiki-logo-href t)
    (:wiki-buttons "WIKI_BUTTONS" nil org-wiki-buttons space)
    (:wiki-sidebar "WIKI_SIDEBAR" nil org-wiki-sidebar t)
    (:wiki-search "WIKI_SEARCH_BOX" nil org-wiki-search t)
    (:wiki-search-action "WIKI_SEARCH" nil org-wiki-search-action t)
    (:wiki-login "WIKI_LOGIN" nil org-wiki-login t)
    (:wiki-login-url "WIKI_LOGIN_URL" nil org-wiki-login-url t)
    (:wiki-personal "WIKI_PERSONAL" nil nil space)
    (:wiki-footer-places "WIKI_FOOTER_PLACES" nil nil space)
    (:wiki-footer-notice "WIKI_FOOTER_NOTICE" nil nil t)
    (:wiki-credit "WIKI_CREDIT" nil org-wiki-credit t)
    (:wiki-latex "WIKI_LATEX" nil org-wiki-latex t)
    (:wiki-pdf "WIKI_PDF" nil org-wiki-pdf t)
    (:wiki-git "WIKI_GIT" nil org-wiki-git t)))


;;; Export commands

(defun org-wiki--environment (&optional subtreep ext-plist file)
  "Return the export channel for the current buffer, as the backend sees it.
SUBTREEP and EXT-PLIST are as for `org-export-as'.  FILE is recorded as
`:input-file', which `org-export-get-environment' does not set."
  (org-combine-plists
   (org-export-get-environment 'wiki subtreep ext-plist)
   (list :input-file (or file (buffer-file-name (buffer-base-buffer))))))

;;;###autoload
(defun org-wiki-export-as-html
    (&optional async subtreep visible-only body-only ext-plist)
  "Export the current buffer to a wiki-skinned HTML buffer.
ASYNC, SUBTREEP, VISIBLE-ONLY, BODY-ONLY and EXT-PLIST are as for
`org-export-to-buffer'."
  (interactive)
  (let ((org-html-htmlize-output-type 'css)
        (org-html-htmlize-font-prefix "org-"))
    (org-export-to-buffer 'wiki "*Org Wiki Export*"
      async subtreep visible-only body-only ext-plist
      (lambda () (set-auto-mode t)))))

;;;###autoload
(defun org-wiki-export-to-html
    (&optional async subtreep visible-only body-only ext-plist)
  "Export the current buffer to a wiki-skinned HTML file.
Also writes the pages the tabs point at -- the source views, the PDF and
the revision history -- unless they are switched off.  ASYNC, SUBTREEP,
VISIBLE-ONLY, BODY-ONLY and EXT-PLIST are as for `org-export-to-file'.
Return the file name."
  (interactive)
  (let ((file (org-wiki--output-file
               (org-export-output-file-name
                (concat "." (or (plist-get ext-plist :html-extension)
                                org-html-extension "html"))
                subtreep)))
        (org-html-htmlize-output-type 'css)
        (org-html-htmlize-font-prefix "org-"))
    (prog1 (org-export-to-file 'wiki file
             async subtreep visible-only body-only ext-plist)
      (unless (or async body-only)
        (require 'ox-wiki-pages)
        (org-wiki-pages-write (org-wiki--environment subtreep ext-plist) file)))))

;;;###autoload
(defun org-wiki-publish-to-html (plist filename pub-dir)
  "Publish FILENAME to PUB-DIR as wiki-skinned HTML, honouring PLIST."
  (let ((org-html-htmlize-output-type 'css)
        (org-html-htmlize-font-prefix "org-"))
    (prog1 (org-publish-org-to 'wiki filename
                               (concat "." (or (plist-get plist :html-extension)
                                               org-html-extension "html"))
                               plist pub-dir)
      (require 'ox-wiki-pages)
      (org-wiki-pages-write
       (with-current-buffer (find-file-noselect filename)
         (org-wiki--environment nil plist filename))
       (expand-file-name (concat (file-name-base filename) ".html") pub-dir)))))

(provide 'ox-wiki)

;;; ox-wiki.el ends here
