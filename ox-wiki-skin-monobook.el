;;; ox-wiki-skin-monobook.el --- the MonoBook skin for ox-wiki -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:

;; MediaWiki's MonoBook, the default from 2004 to 2010 and still maintained.
;; The markup is the skin's own, read off a page served with ?useskin=monobook.
;;
;; It differs from Vector in more than paint, which is the point of keeping the
;; skin separate from the backend: the whole page sits in #globalWrapper, the
;; navigation is one left-hand #column-one rather than a tab row plus a panel,
;; and MonoBook folds the namespace tabs and the action tabs into a single
;; #p-cactions portlet instead of showing two groups.

;;; Code:

(require 'ox-wiki)

(defun org-wiki-monobook--portlet (menu &optional role)
  "Render MENU as a MonoBook portlet.  ROLE is its ARIA role."
  (let* ((id (plist-get menu :id))
         (links (plist-get menu :links))
         (classes (string-join
                   (delq nil (list "portlet" "mw-portlet"
                                   (format "mw-portlet-%s" id)
                                   (unless links "emptyPortlet")))
                   " ")))
    (concat
     (format "<div role=\"%s\" class=\"%s\" id=\"p-%s\" aria-labelledby=\"p-%s-label\">\n"
             (or role "navigation") classes id id)
     (format "\t<h3 id=\"p-%s-label\">%s</h3>\n" id (org-wiki--esc (plist-get menu :label)))
     "\t<div class=\"pBody\">\n\t\t<ul>\n"
     (org-wiki--items menu)
     "\t\t</ul>\n\t</div>\n</div>\n")))

(defun org-wiki-monobook--search (search)
  "Render SEARCH, the search plist, as MonoBook's search portlet."
  (let ((site (org-wiki--esc (plist-get search :sitename))))
    (concat
     "<div role=\"search\" class=\"portlet\" id=\"p-search\">\n"
     "\t<h3 id=\"p-search-label\"><label for=\"searchInput\">Search</label></h3>\n"
     "\t<div class=\"pBody\" id=\"searchBody\">\n"
     (format "\t\t<form action=\"%s\" id=\"searchform\">"
             (org-wiki--esc (plist-get search :action)))
     (mapconcat (lambda (field)
                  (format "<input type=\"hidden\" name=\"%s\" value=\"%s\">"
                          (org-wiki--esc (car field)) (org-wiki--esc (cdr field))))
                (plist-get search :fields) "")
     (format (concat "<input type=\"search\" name=\"%s\" placeholder=\"Search %s\""
                     " aria-label=\"Search %s\" autocapitalize=\"none\""
                     " spellcheck=\"false\" accesskey=\"f\" id=\"searchInput\">")
             (org-wiki--esc (plist-get search :name)) site site)
     "<input type=\"submit\" value=\"Go\" title=\"Go\" class=\"searchButton\""
     " id=\"searchButton\"> "
     "<input type=\"submit\" value=\"Search\" title=\"Search\""
     " class=\"searchButton mw-fallbackSearchButton\" id=\"mw-searchButton\">"
     "</form>\n\t</div>\n</div>\n")))

(defun org-wiki-monobook--footer (page)
  "Render PAGE's footer in MonoBook's shape."
  (concat
   "<div id=\"footer\" class=\"mw-footer\" role=\"contentinfo\">\n"
   (mapconcat
    (lambda (b)
      (format "\t<div class=\"footer-icons\">%s<img src=\"%s\" alt=\"%s\" loading=\"lazy\">%s</div>\n"
              (if (plist-get b :href)
                  (format "<a href=\"%s\">" (org-wiki--esc (plist-get b :href))) "")
              (plist-get b :src)
              (org-wiki--esc (plist-get b :alt))
              (if (plist-get b :href) "</a>" "")))
    (plist-get page :footer-buttons) "")
   "\t<ul id=\"f-list\">\n"
   (mapconcat (lambda (line) (format "\t\t<li>%s</li>\n" line))
              (plist-get page :footer-info) "")
   (mapconcat
    (lambda (l)
      (format "\t\t<li%s><a%s>%s</a></li>\n"
              (org-wiki--attr "id" (plist-get l :id))
              (org-wiki--attr "href" (or (plist-get l :href) "#"))
              (org-wiki--esc (plist-get l :text))))
    (plist-get page :footer-places) "")
   "\t</ul>\n</div>\n"))

(defun org-wiki-monobook-page (page)
  "Render PAGE, the page plist, as a MonoBook document body."
  (let ((logo (plist-get page :logo)))
    (concat
     (format "<body class=\"%s skin--responsive\">\n" (org-wiki-body-class page))
     "<div id=\"globalWrapper\">\n"
     "<div id=\"column-content\">\n"
     "<div id=\"content\" class=\"mw-body\" role=\"main\">\n"
     "\t<a id=\"top\"></a>\n"
     "\t<div id=\"siteNotice\"></div>\n"
     "\t<div class=\"mw-indicators\"></div>\n"
     (format "\t<h1 id=\"firstHeading\" class=\"firstHeading mw-first-heading\">%s</h1>\n"
             (plist-get page :title))
     "\t<div id=\"bodyContent\" class=\"monobook-body\">\n"
     (format "\t\t<div id=\"siteSub\">%s</div>\n"
             (org-wiki--esc (plist-get page :tagline)))
     (format "\t\t<div id=\"contentSub\">%s</div>\n" (or (plist-get page :subtitle) ""))
     (format "\t\t<div id=\"mw-content-text\" class=\"mw-body-content mw-content-ltr\" lang=\"%s\" dir=\"ltr\">\n"
             (org-wiki--esc (plist-get page :lang)))
     (plist-get page :content)
     "\t\t</div>\n\t</div>\n</div>\n</div>\n"
     "<div id=\"column-one\">\n<h2>Navigation menu</h2>\n"
     ;; MonoBook has one tab portlet, not two groups, so the namespace tabs and
     ;; the action tabs are concatenated into it.
     (org-wiki-monobook--portlet
      (list :id "cactions" :label "Page actions"
            :links (append (plist-get (plist-get page :namespace-tabs) :links)
                           (plist-get (plist-get page :action-tabs) :links))))
     (if (plist-get page :personal)
         (org-wiki-monobook--portlet (plist-get page :personal))
       "")
     "<div class=\"portlet\" id=\"p-logo\" role=\"banner\">\n"
     (format "\t<a href=\"%s\" class=\"mw-wiki-logo\" title=\"Visit the main page\"></a>\n"
             (org-wiki--esc (plist-get logo :href)))
     "</div>\n"
     "<div id=\"sidebar\">\n"
     (mapconcat #'org-wiki-monobook--portlet (plist-get page :sidebar) "")
     (if (plist-get page :search) (org-wiki-monobook--search (plist-get page :search)) "")
     "</div>\n</div>\n"
     "<div class=\"visualClear\"></div>\n"
     (org-wiki-monobook--footer page)
     "</div>\n</body>\n")))

(org-wiki-define-skin 'monobook
  :title "MonoBook"
  :stylesheets '("css/monobook.css")
  :body-class "skin-monobook"
  :credit (concat "Presentation adapted from MediaWiki's skins, which are"
                 " copyright the MediaWiki contributors and licensed"
                 " GPL-2.0-or-later.")
  :page #'org-wiki-monobook-page)

(provide 'ox-wiki-skin-monobook)

;;; ox-wiki-skin-monobook.el ends here
