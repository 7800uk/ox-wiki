;;; ox-wiki-skin-vector.el --- the Vector legacy skin for ox-wiki -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:

;; MediaWiki's "Vector legacy" -- the 2010 Vector, still shipped as the `vector'
;; skin next to `vector-2022'.  The markup here is the skin's own, read off a
;; page served with ?useskin=vector; the stylesheet beside it is MediaWiki's,
;; vendored.
;;
;; This file is a worked example of what a skin owes ox-wiki: a `:page'
;; function, taking the page plist that `org-wiki--page' builds and returning
;; everything from <body> to </body>.  Shared helpers do the parts every skin
;; has in common -- `org-wiki--items' for a menu's list items,
;; `org-wiki-body-class' for the <body> classes, `org-wiki--esc' for escaping.

;;; Code:

(require 'ox-wiki)

(defun org-wiki-vector--portlet (menu &optional extra-class dropdown)
  "Render MENU as a Vector portlet.
EXTRA-CLASS is appended to the <nav> class list, for instance
\"vector-menu-portal portal\" in the sidebar.  DROPDOWN makes it one of
Vector's checkbox dropdowns."
  (let* ((id (plist-get menu :id))
         (label (plist-get menu :label))
         (links (plist-get menu :links))
         (heading-tag (if dropdown "label" "h3"))
         (classes (string-join
                   (delq nil (list "mw-portlet"
                                   (format "mw-portlet-%s" id)
                                   (unless links "emptyPortlet")
                                   (plist-get menu :class)
                                   extra-class
                                   "vector-menu"))
                   " ")))
    (concat
     (format "<nav id=\"p-%s\" class=\"%s\" aria-labelledby=\"p-%s-label\">\n"
             id classes id)
     (when dropdown
       (format (concat "\t<input type=\"checkbox\" id=\"p-%s-checkbox\" role=\"button\""
                       " aria-haspopup=\"true\" class=\"vector-menu-checkbox\""
                       " aria-labelledby=\"p-%s-label\">\n")
               id id))
     (format "\t<%s id=\"p-%s-label\" class=\"vector-menu-heading\">\n" heading-tag id)
     (format "\t\t<span class=\"vector-menu-heading-label\">%s</span>\n"
             (org-wiki--esc label))
     (format "\t</%s>\n" heading-tag)
     "\t<div class=\"vector-menu-content\">\n"
     "\t\t<ul class=\"vector-menu-content-list\">\n"
     (org-wiki--items menu t)
     "\t\t</ul>\n"
     "\t</div>\n"
     "</nav>\n")))

(defun org-wiki-vector--tabs (menu)
  "Render MENU as a Vector tab group."
  (org-wiki-vector--portlet
   (org-combine-plists menu
                       '(:class "vector-menu-tabs vector-menu-tabs-legacy"))))

(defun org-wiki-vector--search (search)
  "Render SEARCH, the search plist, as Vector's search box."
  (let ((site (org-wiki--esc (plist-get search :sitename))))
    (concat
     "<div id=\"p-search\" role=\"search\" class=\"vector-search-box-vue"
     " vector-search-box-show-thumbnail vector-search-box-auto-expand-width"
     " vector-search-box\">\n"
     "\t<h3>Search</h3>\n"
     (format "\t<form action=\"%s\" id=\"searchform\" class=\"vector-search-box-form\">\n"
             (org-wiki--esc (plist-get search :action)))
     "\t\t<div id=\"simpleSearch\" class=\"vector-search-box-inner\""
     " data-search-loc=\"header-navigation\">\n"
     (format (concat "\t\t\t<input class=\"vector-search-box-input\" type=\"search\""
                     " name=\"%s\" placeholder=\"Search %s\" aria-label=\"Search %s\""
                     " autocapitalize=\"none\" spellcheck=\"false\" accesskey=\"f\""
                     " id=\"searchInput\">\n")
             (org-wiki--esc (plist-get search :name)) site site)
     (mapconcat (lambda (field)
                  (format "\t\t\t<input type=\"hidden\" name=\"%s\" value=\"%s\">\n"
                          (org-wiki--esc (car field)) (org-wiki--esc (cdr field))))
                (plist-get search :fields) "")
     "\t\t\t<input id=\"mw-searchButton\" class=\"searchButton mw-fallbackSearchButton\""
     " type=\"submit\" title=\"Search\" value=\"Search\">\n"
     "\t\t\t<input id=\"searchButton\" class=\"searchButton\" type=\"submit\""
     " title=\"Search\" value=\"Go\">\n"
     "\t\t</div>\n\t</form>\n</div>\n")))

(defun org-wiki-vector--footer (page)
  "Render PAGE's footer in Vector's shape."
  (concat
   "<footer id=\"footer\" class=\"mw-footer\">\n"
   "\t<ul id=\"footer-info\" class=\"mw-portlet mw-portlet-footer-info\">\n"
   (mapconcat (lambda (line) (format "\t\t<li>%s</li>\n" line))
              (plist-get page :footer-info) "")
   "\t</ul>\n"
   "\t<ul id=\"footer-places\" class=\"mw-portlet mw-portlet-footer-places\">\n"
   (mapconcat
    (lambda (l)
      (format "\t\t<li%s><a%s>%s</a></li>\n"
              (org-wiki--attr "id" (plist-get l :id))
              (org-wiki--attr "href" (or (plist-get l :href) "#"))
              (org-wiki--esc (plist-get l :text))))
    (plist-get page :footer-places) "")
   "\t</ul>\n"
   "\t<ul id=\"footer-icons\" class=\"mw-portlet mw-portlet-footer-icons noprint\">\n"
   (mapconcat
    (lambda (b)
      (format "\t\t<li class=\"footer-icon\">%s<img src=\"%s\" alt=\"%s\" loading=\"lazy\">%s</li>\n"
              (if (plist-get b :href)
                  (format "<a href=\"%s\">" (org-wiki--esc (plist-get b :href))) "")
              (plist-get b :src)
              (org-wiki--esc (plist-get b :alt))
              (if (plist-get b :href) "</a>" "")))
    (plist-get page :footer-buttons) "")
   "\t</ul>\n"
   "</footer>\n"))

(defun org-wiki-vector-page (page)
  "Render PAGE, the page plist, as a Vector legacy document body."
  (let ((lang (org-wiki--esc (plist-get page :lang)))
        (logo (plist-get page :logo)))
    (concat
     (format "<body class=\"%s\">\n" (org-wiki-body-class page))
     "<div id=\"mw-page-base\" class=\"noprint\"></div>\n"
     "<div id=\"mw-head-base\" class=\"noprint\"></div>\n"
     "<div id=\"content\" class=\"mw-body\" role=\"main\">\n"
     "\t<a id=\"top\"></a>\n"
     "\t<div id=\"siteNotice\"></div>\n"
     "\t<div class=\"mw-indicators\"></div>\n"
     (format (concat "\t<h1 id=\"firstHeading\" class=\"firstHeading mw-first-heading\">"
                     "<span class=\"mw-page-title-main\">%s</span></h1>\n")
             (plist-get page :title))
     "\t<div id=\"bodyContent\" class=\"vector-body\">\n"
     (format "\t\t<div id=\"siteSub\" class=\"noprint\">%s</div>\n"
             (org-wiki--esc (plist-get page :tagline)))
     (format "\t\t<div id=\"contentSub\">%s</div>\n" (or (plist-get page :subtitle) ""))
     "\t\t<div id=\"contentSub2\"></div>\n"
     "\t\t<div id=\"jump-to-nav\"></div>\n"
     "\t\t<a class=\"mw-jump-link\" href=\"#mw-head\">Jump to navigation</a>\n"
     (if (plist-get page :search)
         "\t\t<a class=\"mw-jump-link\" href=\"#searchInput\">Jump to search</a>\n"
       "")
     (format "\t\t<div id=\"mw-content-text\" class=\"mw-body-content mw-content-ltr\" lang=\"%s\" dir=\"ltr\">\n"
             lang)
     (plist-get page :content)
     "\t\t</div>\n\t</div>\n</div>\n"
     "<div id=\"mw-navigation\">\n<h2>Navigation menu</h2>\n"
     "<div id=\"mw-head\">\n"
     (if (plist-get page :personal)
         (org-wiki-vector--portlet
          (org-combine-plists (plist-get page :personal)
                              '(:class "vector-user-menu-legacy")))
       "")
     "<div id=\"left-navigation\">\n"
     (org-wiki-vector--tabs (plist-get page :namespace-tabs))
     "</div>\n<div id=\"right-navigation\">\n"
     (org-wiki-vector--tabs (plist-get page :action-tabs))
     (if (plist-get page :search) (org-wiki-vector--search (plist-get page :search)) "")
     "</div>\n</div>\n"
     "<div id=\"mw-panel\" class=\"vector-legacy-sidebar\">\n"
     "<div id=\"p-logo\" role=\"banner\">\n"
     (format "\t<a class=\"mw-wiki-logo\" href=\"%s\" title=\"Visit the main page\"></a>\n"
             (org-wiki--esc (plist-get logo :href)))
     "</div>\n"
     (mapconcat (lambda (m) (org-wiki-vector--portlet m "vector-menu-portal portal"))
                (plist-get page :sidebar) "")
     "</div>\n</div>\n"
     (org-wiki-vector--footer page)
     "</body>\n")))

(org-wiki-define-skin 'vector
  :title "Vector legacy"
  :stylesheets '("css/vector.css")
  :body-class "skin-vector-legacy skin-vector"
  :credit (concat "Presentation adapted from MediaWiki's skins, which are"
                 " copyright the MediaWiki contributors and licensed"
                 " GPL-2.0-or-later.")
  :page #'org-wiki-vector-page)

(provide 'ox-wiki-skin-vector)

;;; ox-wiki-skin-vector.el ends here
