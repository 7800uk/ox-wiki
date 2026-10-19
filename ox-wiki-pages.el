;;; ox-wiki-pages.el --- the pages ox-wiki's tabs point at -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:

;; Beside the article, ox-wiki writes the pages its tabs lead to:
;;
;;   <name>-source.html        the Org text, read-only, with a download button
;;   <name>-source-latex.html  the same for the LaTeX export
;;   <name>.pdf                that LaTeX, compiled
;;   <name>-history.html       git's revisions of the file
;;   <name>-diff-<sha>.html    what one revision changed
;;   <name>-diff-<sha>-cur.html  what has changed since it
;;
;; They wear the same skin as the article, because they go through the same
;; `org-wiki--document'.  Each is optional; see `org-wiki-features'.
;;
;; None of this is a wiki: there is nothing to save to.  MediaWiki's own
;; read-only "view source" page is the closest thing it has, so that is what the
;; source views imitate, down to calling the button "Download source" where a
;; wiki would say "Publish changes".

;;; Code:

(require 'ox-wiki)
(require 'cl-lib)
(require 'subr-x)

(defcustom org-wiki-history-date-format "%Y-%m-%d %H:%M"
  "How revision dates are shown on the history page."
  :group 'org-wiki
  :type 'string)

(defun org-wiki--write (file string)
  "Write STRING to FILE, and return FILE."
  (make-directory (file-name-directory file) t)
  (let ((coding-system-for-write 'utf-8))
    (with-temp-file file (insert string)))
  file)

(defun org-wiki--page-title (info)
  "Return the document title in INFO as a plain string."
  (let ((title (plist-get info :title)))
    (or (org-string-nw-p (string-trim (org-wiki--plain title info)))
        (org-string-nw-p (file-name-base (or (plist-get info :input-file) "")))
        "Untitled")))


;;; Source views

(defun org-wiki--source-tabs (info kind)
  "Return the left-hand tabs for a source view.
INFO is the export channel and KIND is `org' or `latex'; the other tab is
left out when LaTeX is switched off."
  (let ((file (or (plist-get info :input-file) "page")))
    (list :id "namespaces" :label "Namespaces"
          :links
          (delq nil
                (list (list :text "Org source" :id "ca-nstab-org"
                            :href (org-wiki--companion file "source")
                            :selected (eq kind 'org))
                      (when (plist-get (org-wiki-features info) :latex)
                        (list :text "LaTeX source" :id "ca-nstab-latex"
                              :href (org-wiki--companion file "source-latex")
                              :selected (eq kind 'latex))))))))

(defun org-wiki--source-body (text download-name)
  "Return the content of a source view showing TEXT.
DOWNLOAD-NAME is what the download button saves the file as."
  (concat
   "<div class=\"mw-parser-output\">\n"
   "<p>You can view and copy the source of this page.  It is read-only:"
   " the page is generated from an Org file, so there is nothing here to save to.</p>\n"
   "<div class=\"mw-editform\">\n"
   (format (concat "<textarea readonly id=\"wpTextbox1\" name=\"wpTextbox1\""
                   " class=\"mw-editfont-monospace\" rows=\"25\" cols=\"80\""
                   " aria-label=\"Page source\" spellcheck=\"false\">%s</textarea>\n")
           (org-wiki--esc text))
   "<div class=\"editOptions\">\n"
   (format (concat "<a class=\"cdx-button cdx-button--action-progressive"
                   " cdx-button--weight-primary\" download=\"%s\" href=\"%s\">"
                   "Download source</a>\n")
           (org-wiki--esc download-name)
           (org-wiki--text-data-uri text))
   "</div>\n</div>\n</div>\n"))

(defun org-wiki--latex-source (info)
  "Return the LaTeX export of the current buffer as a string.
INFO is unused but kept so the callers read alike."
  (ignore info)
  (require 'ox-latex)
  (org-export-as 'latex nil nil nil nil))

(defun org-wiki--source-document (info kind)
  "Return the source-view document for KIND, `org' or `latex'.
INFO is the export communication channel."
  (let* ((file (plist-get info :input-file))
         (title (org-wiki--page-title info))
         (text (pcase kind
                 ('latex (org-wiki--latex-source info))
                 (_ (with-temp-buffer (insert-file-contents file) (buffer-string)))))
         (download (concat (file-name-base file)
                           (if (eq kind 'latex) ".tex" ".org"))))
    (org-wiki--document
     (org-wiki--page
      info
      :action "edit"
      :title (format "View source for %s" (org-wiki--esc title))
      :subtitle (format "&#8592; <a href=\"%s\">%s</a>"
                        (org-wiki--esc (file-name-nondirectory
                                        (concat (file-name-base file) ".html")))
                        (org-wiki--esc title))
      :namespace-tabs (org-wiki--source-tabs info kind)
      :action-tabs (org-wiki-action-tabs info 'source)
      :content (org-wiki--source-body text download)))))


;;; Revision history, from git

(defun org-wiki--git (file &rest args)
  "Run git with ARGS in FILE's directory and return its output, or nil."
  (let ((default-directory (file-name-directory (expand-file-name file))))
    (with-temp-buffer
      (when (zerop (apply #'call-process "git" nil t nil args))
        (buffer-string)))))

(defun org-wiki--revisions (file limit)
  "Return up to LIMIT revisions of FILE as plists, newest first."
  (let ((out (org-wiki--git file "log" (format "-n%d" limit)
                            "--date=iso-strict"
                            "--format=%H%x1f%an%x1f%ad%x1f%s"
                            "--" (file-name-nondirectory file))))
    (when out
      (delq nil
            (mapcar (lambda (line)
                      (let ((parts (split-string line "\x1f")))
                        (when (= (length parts) 4)
                          (list :sha (nth 0 parts)
                                :author (nth 1 parts)
                                :date (nth 2 parts)
                                :subject (nth 3 parts)))))
                    (split-string (string-trim out) "\n" t))))))

(defun org-wiki--diff-table (diff otitle ntitle)
  "Render DIFF, a unified diff, as MediaWiki's two-column diff table.
OTITLE and NTITLE head the left and right columns; both are HTML."
  (let ((rows nil) (dels nil) (adds nil))
    (cl-labels
        ((side (marker class text)
           (format "<td class=\"diff-marker\"%s></td><td class=\"%s\"><div>%s</div></td>"
                   (if marker (format " data-marker=\"%s\"" marker) "")
                   class (org-wiki--esc text)))
         (blank () "<td colspan=\"2\" class=\"diff-empty\">&#160;</td>")
         (flush ()
           (let ((d (nreverse dels)) (a (nreverse adds)))
             (setq dels nil adds nil)
             (dotimes (i (max (length d) (length a)))
               (let ((old (nth i d)) (new (nth i a)))
                 (push (concat "<tr>"
                               (if old (side "−" "diff-deletedline" old) (blank))
                               (if new (side "+" "diff-addedline" new) (blank))
                               "</tr>")
                       rows))))))
      (dolist (line (split-string (or diff "") "\n"))
        (cond
         ((string-prefix-p "@@" line)
          (flush)
          (when (string-match "@@ -\\([0-9]+\\)[,0-9]* \\+\\([0-9]+\\)" line)
            (push (format (concat "<tr><td colspan=\"2\" class=\"diff-lineno\">Line %s:</td>"
                                  "<td colspan=\"2\" class=\"diff-lineno\">Line %s:</td></tr>")
                          (match-string 1 line) (match-string 2 line))
                  rows)))
         ;; git's file headers carry no information the titles do not.
         ((string-match-p "\\`\\(diff \\|index \\|--- \\|\\+\\+\\+ \\|new file\\|deleted file\\|old mode\\|new mode\\|similarity\\|rename \\|Binary \\)" line)
          nil)
         ((string-prefix-p "-" line) (push (substring line 1) dels))
         ((string-prefix-p "+" line) (push (substring line 1) adds))
         ((string-prefix-p " " line)
          (flush)
          (let ((text (substring line 1)))
            (push (concat "<tr>" (side nil "diff-context" text)
                          (side nil "diff-context" text) "</tr>")
                  rows)))
         (t nil)))
      (flush))
    (when rows
      (concat
       "<table class=\"diff diff-contentalign-left diff-editfont-monospace\">\n"
       "<col class=\"diff-marker\"><col class=\"diff-content\">"
       "<col class=\"diff-marker\"><col class=\"diff-content\">\n<tbody>\n"
       (format (concat "<tr class=\"diff-title\"><td colspan=\"2\" class=\"diff-otitle\">%s</td>"
                       "<td colspan=\"2\" class=\"diff-ntitle\">%s</td></tr>\n")
               otitle ntitle)
       (mapconcat #'identity (nreverse rows) "\n")
       "\n</tbody>\n</table>\n"))))

(defun org-wiki--diff-name (file sha &optional to-current)
  "Return the file name of FILE's diff page for revision SHA.
TO-CURRENT asks for the diff against the file as it stands now, which is
what MediaWiki's `cur\' link shows, rather than against SHA's parent."
  (format "%s-diff-%s%s.html"
          (file-name-base file) (substring sha 0 7) (if to-current "-cur" "")))

(defun org-wiki--revision-label (revision)
  "Return a short HTML label for REVISION."
  (format "<b>%s</b> by %s<br><span class=\"comment\">%s</span>"
          (org-wiki--esc (org-wiki--revision-date revision))
          (org-wiki--esc (plist-get revision :author))
          (org-wiki--esc (plist-get revision :subject))))

(defun org-wiki--revision-date (revision)
  "Return REVISION\'s date, formatted with `org-wiki-history-date-format\'."
  (condition-case nil
      (format-time-string org-wiki-history-date-format
                          (date-to-time (plist-get revision :date)))
    (error (plist-get revision :date))))

(defun org-wiki--revision-diff (file revision to-current)
  "Return the unified diff for REVISION of FILE, as a string or nil.
TO-CURRENT diffs against HEAD rather than against the revision\'s parent.
`git show\' is used for the latter rather than `git diff SHA^ SHA\', so that
the commit which created the file works too."
  (let ((name (file-name-nondirectory file))
        (sha (plist-get revision :sha)))
    (if to-current
        (org-wiki--git file "diff" "--no-color" "-U2" sha "HEAD" "--" name)
      (org-wiki--git file "show" "--no-color" "--format=" "-U2" sha "--" name))))

(defun org-wiki--history-body (file revisions)
  "Render the history of FILE from REVISIONS, newest first.
Each revision\'s `cur\' and `prev\' link leads to a page of its own."
  (let* ((name (file-name-nondirectory file))
         (newest (car revisions)))
    (concat
     "<div class=\"mw-parser-output\">\n"
     (format (concat "<p>Revisions of <code>%s</code>, from git.  Renames are not"
                     " followed, so the file has history only under the path it"
                     " has now, and the %d most recent revisions are the ones"
                     " with diffs.</p>\n")
             (org-wiki--esc name) org-wiki-history-limit)
     "<ul id=\"pagehistory\" class=\"mw-contributions-list\">\n"
     (mapconcat
      (lambda (rev)
        (let ((sha (plist-get rev :sha)))
          (concat
           "<li>"
           "<span class=\"mw-history-histlinks mw-changeslist-links\">"
           (if (eq rev newest)
               "<span>cur</span>"
             (format "<span><a href=\"%s\">cur</a></span>"
                     (org-wiki--esc (org-wiki--diff-name file sha t))))
           (format "<span><a href=\"%s\">prev</a></span></span> "
                   (org-wiki--esc (org-wiki--diff-name file sha)))
           (format "<a class=\"mw-changeslist-date\" href=\"%s\">%s</a>"
                   (org-wiki--esc (org-wiki--diff-name file sha))
                   (org-wiki--esc (org-wiki--revision-date rev)))
           (format " <span class=\"history-user\">%s</span>"
                   (org-wiki--esc (plist-get rev :author)))
           (format " <span class=\"comment comment--without-parentheses\">%s</span>"
                   (org-wiki--esc (plist-get rev :subject)))
           (format " <code class=\"mw-revid\">%s</code>" (substring sha 0 7))
           "</li>")))
      revisions "\n")
     "\n</ul>\n</div>\n")))

(defun org-wiki--history-document (info revisions)
  "Return the revision-history document for REVISIONS.
INFO is the export communication channel."
  (let ((file (plist-get info :input-file))
        (title (org-wiki--page-title info)))
    (org-wiki--document
     (org-wiki--page
      info
      :action "history"
      :title (format "%s: Revision history" (org-wiki--esc title))
      :subtitle (format "&#8592; <a href=\"%s\">%s</a>"
                        (org-wiki--esc (concat (file-name-base file) ".html"))
                        (org-wiki--esc title))
      :action-tabs (org-wiki-action-tabs info 'history)
      :content (if revisions
                   (org-wiki--history-body file revisions)
                 "<div class=\"mw-parser-output\"><p>git reports no revisions \
for this file.</p></div>\n")))))

(defun org-wiki--diff-document (info revision to-current)
  "Return the diff page for REVISION.  INFO is the export channel.
TO-CURRENT asks for the diff against the file as it stands, not against the
revision\'s parent."
  (let* ((file (plist-get info :input-file))
         (title (org-wiki--page-title info))
         (sha (plist-get revision :sha))
         (table (org-wiki--diff-table
                 (org-wiki--revision-diff file revision to-current)
                 (if to-current
                     (org-wiki--revision-label revision)
                   (format "Revision before %s" (substring sha 0 7)))
                 (if to-current
                     "<b>Current revision</b>"
                   (org-wiki--revision-label revision)))))
    (org-wiki--document
     (org-wiki--page
      info
      :action "history"
      :title (format "Difference between revisions of &#8220;%s&#8221;"
                     (org-wiki--esc title))
      :subtitle (format (concat "&#8592; <a href=\"%s\">%s</a>"
                                " &#183; <a href=\"%s\">Revision history</a>")
                        (org-wiki--esc (concat (file-name-base file) ".html"))
                        (org-wiki--esc title)
                        (org-wiki--esc (org-wiki--companion file "history")))
      :action-tabs (org-wiki-action-tabs info 'history)
      :content
      (concat
       "<div class=\"mw-parser-output\">\n"
       (format (concat "<div class=\"mw-diff-table-prefix\"><p>%s of <code>%s</code>,"
                       " commit <code>%s</code>.</p></div>\n")
               (if to-current "Changes since this revision" "The change made by this revision")
               (org-wiki--esc (file-name-nondirectory file))
               (org-wiki--esc (substring sha 0 7)))
       (or table
           "<p class=\"diff-notice\">This revision left the file unchanged at \
this path.</p>\n")
       "</div>\n")))))


;;; PDF

(defun org-wiki--write-pdf (directory)
  "Export the current buffer to PDF through LaTeX, landing it in DIRECTORY.
Returns the PDF's name, or nil when LaTeX failed -- which it reports rather
than raising, so one unhappy file does not stop a publish."
  (require 'ox-latex)
  (condition-case err
      (let ((pdf (org-latex-export-to-pdf)))
        ;; org-latex keeps the .tex beside the PDF; the LaTeX source already has
        ;; a page of its own, so the stray file is only clutter.
        (let ((tex (concat (file-name-sans-extension (or pdf "")) ".tex")))
          (when (and pdf (file-exists-p tex)) (delete-file tex)))
        (when (and pdf (file-exists-p pdf))
          (let ((target (expand-file-name (file-name-nondirectory pdf) directory)))
            (unless (file-equal-p pdf target)
              (rename-file pdf target t))
            (file-name-nondirectory target))))
    (error
     (message "ox-wiki: LaTeX export failed (%s); the View PDF tab will not resolve"
              (error-message-string err))
     nil)))


;;; Entry point

;;;###autoload
(defun org-wiki-pages-write (info html-file)
  "Write the companion pages for the article at HTML-FILE.
INFO is the export communication channel, as `org-wiki--environment'
returns it.  Which pages appear is decided by `org-wiki-features'."
  (let* ((source (plist-get info :input-file))
         (features (org-wiki-features info))
         (directory (file-name-directory (expand-file-name html-file))))
    (when (and source (file-readable-p source))
      (org-wiki--write
       (expand-file-name (org-wiki--companion source "source") directory)
       (org-wiki--source-document info 'org))
      (when (plist-get features :latex)
        (org-wiki--write
         (expand-file-name (org-wiki--companion source "source-latex") directory)
         (org-wiki--source-document info 'latex)))
      (when (plist-get features :pdf)
        (org-wiki--write-pdf directory))
      (when (plist-get features :git)
        (let ((revisions (org-wiki--revisions source org-wiki-history-limit)))
          (org-wiki--write
           (expand-file-name (org-wiki--companion source "history") directory)
           (org-wiki--history-document info revisions))
          ;; One page per revision, the way a wiki gives every cur/prev link a
          ;; page: the change this revision made, and -- except for the newest,
          ;; where there is nothing to compare -- what has changed since it.
          (dolist (revision revisions)
            (dolist (to-current (if (eq revision (car revisions)) '(nil) '(nil t)))
              (org-wiki--write
               (expand-file-name
                (org-wiki--diff-name source (plist-get revision :sha) to-current)
                directory)
               (org-wiki--diff-document info revision to-current)))))))))

(provide 'ox-wiki-pages)

;;; ox-wiki-pages.el ends here
