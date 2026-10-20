;;; build.el --- rebuild the ox-wiki demo -*- lexical-binding: t; -*-

;; Run with no init file in the way:
;;
;;   emacs -Q --batch -l demo/build.el
;;
;; Everything lands in build/ at the top of this repository -- never beside the
;; Org sources, and never in version control -- so a demo build leaves the
;; working tree as it found it.  Open build/Demo.html to look at the result.
;;
;; Writes Demo.html and its companion pages in the Vector skin,
;; Demo-monobook.html in MonoBook and Demo-citizen.html in Citizen.  The PDF
;; needs a LaTeX installation and the revision history needs the file to be
;; committed; both are skipped, with a message, when they cannot be produced.

;;; Code:

(let* ((here (file-name-directory (or load-file-name buffer-file-name)))
       (root (expand-file-name ".." here)))
  (add-to-list 'load-path root)
  (require 'ox-wiki)
  (let ((org-wiki-output-directory (expand-file-name "build" root)))
    (dolist (name '("Demo.org" "Demo-monobook.org" "Demo-citizen.org"))
      (with-current-buffer (find-file-noselect (expand-file-name name here))
        (message "ox-wiki: wrote %s" (org-wiki-export-to-html))))))

;;; build.el ends here
