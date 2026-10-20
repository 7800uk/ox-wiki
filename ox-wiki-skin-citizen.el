;;; ox-wiki-skin-citizen.el --- the Citizen skin for ox-wiki -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Citizen, the StarCitizenTools skin: a narrow icon rail for a header, the
;; navigation in a drawer that opens from it, the page tabs as icon buttons
;; under the title, and the table of contents in a column beside the article.
;; The markup is the skin's own, read off a page served by a wiki running it
;; (starcitizen.tools) and checked against its Mustache templates; the
;; stylesheet beside it is Citizen's ResourceLoader output, vendored.
;;
;; Citizen leans on JavaScript for its preferences panel, share dialog, sticky
;; header and the scroll-tracking of its contents, and none of that is here.
;; What is here works without it, because Citizen's own dropdowns are <details>
;; elements that its stylesheet opens and closes: the search card, the drawer
;; and the personal menu.
;;
;; Two things set it apart from Vector and MonoBook.  It draws the table of
;; contents itself, in the side column, so it asks for `:own-toc' and builds
;; the list from the page plist's `:toc' instead of having MediaWiki's #toc
;; placed in the article.  And it themes from classes on <html>; the theme is
;; `skin-theme-clientpref-os', so the page follows the reader's light or dark
;; setting, as Citizen does by default.
;;
;; Citizen is GPL-3.0-or-later, and so is this file, which follows its markup.

;;; Code:

(require 'ox-wiki)

(defconst org-wiki-citizen--button
  "cdx-button cdx-button--fake-button cdx-button--fake-button--enabled"
  "The classes that make a link look like a Codex button.")

(defconst org-wiki-citizen--icon-button
  (concat "citizen-dropdown-summary citizen-cdx-button--size-large "
          org-wiki-citizen--button
          " cdx-button--icon-only cdx-button--weight-quiet")
  "The classes of an icon-only header button.")

(defconst org-wiki-citizen--icons
  '(("ca-nstab-main" . "article")
    ("ca-view" . "eye")
    ("ca-viewsource" . "wikiText")
    ("ca-pdf" . "printer")
    ("ca-history" . "history")
    ("n-mainpage" . "home")
    ("n-mainpage-description" . "home")
    ("n-recentchanges" . "recentChanges")
    ("t-print" . "printer")
    ("pt-anonuserpage" . "userAvatar"))
  "Icons for the links that MediaWiki gives one, by link id.
Citizen only draws an icon where it knows the link, so links not named here
go without, as on a real wiki.")

(defconst org-wiki-citizen--menu-svg
  (concat
   "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\""
   " viewBox=\"0 0 20 20\" aria-hidden=\"true\">"
   "<rect x=\"1\" y=\"3\" width=\"18\" height=\"2\" fill=\"currentcolor\" rx=\"1\"/>"
   "<rect x=\"1\" y=\"9\" width=\"18\" height=\"2\" fill=\"currentcolor\" rx=\"1\"/>"
   "<rect x=\"1\" y=\"15\" width=\"18\" height=\"2\" fill=\"currentcolor\" rx=\"1\"/>"
   "</svg>")
  "Citizen's hamburger, from templates/Icon__menu.mustache.
Inline rather than an icon class, because its stylesheet animates the bars
into a cross when the drawer opens.")

(defconst org-wiki-citizen--search-svg
  (concat
   "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\""
   " viewBox=\"0 0 20 20\" aria-hidden=\"true\">"
   "<circle cx=\"8\" cy=\"8\" r=\"6\" fill=\"none\" stroke=\"currentcolor\" stroke-width=\"2\"/>"
   "<line class=\"citizen-icon-search__handle\" x1=\"12.5\" y1=\"12.5\" x2=\"18\" y2=\"18\""
   " stroke=\"currentcolor\" stroke-width=\"2\" stroke-linecap=\"round\"/>"
   "<line class=\"citizen-icon-search__close\" x1=\"3.6\" y1=\"3.6\" x2=\"16.4\" y2=\"16.4\""
   " stroke=\"currentcolor\" stroke-width=\"2\" stroke-linecap=\"round\"/>"
   "<line class=\"citizen-icon-search__close\" x1=\"16.4\" y1=\"3.6\" x2=\"3.6\" y2=\"16.4\""
   " stroke=\"currentcolor\" stroke-width=\"2\" stroke-linecap=\"round\"/>"
   "</svg>")
  "Citizen's search icon, from templates/Icon__search.mustache.")

(defun org-wiki-citizen--icon (name &optional tag)
  "Return the element Citizen draws icon NAME with.  TAG defaults to span."
  (let ((tag (or tag "span")))
    (format "<%s class=\"citizen-ui-icon mw-ui-icon-%s mw-ui-icon-wikimedia-%s\"></%s>"
            tag name name tag)))

(defun org-wiki-citizen--item (link &optional link-class)
  "Render LINK as a Citizen menu item.  LINK-CLASS goes on the <a>."
  (let* ((icon (alist-get (plist-get link :id) org-wiki-citizen--icons
                          nil nil #'equal))
         (label (concat (if icon (concat (org-wiki-citizen--icon icon) " ") "")
                        (format "<span>%s</span>"
                                (org-wiki--esc (plist-get link :text)))))
         (href (plist-get link :href)))
    (concat "<li"
            (org-wiki--attr "id" (plist-get link :id))
            (format " class=\"%smw-list-item\""
                    (if (plist-get link :selected) "selected " ""))
            ">"
            (if href
                (concat "<a"
                        (org-wiki--attr "href" href)
                        (org-wiki--attr "class" link-class)
                        (org-wiki--attr "title" (plist-get link :title))
                        (org-wiki--attr "accesskey" (plist-get link :accesskey))
                        ">" label "</a>")
              label)
            "</li>")))

(defun org-wiki-citizen--menu (menu &optional link-class)
  "Render MENU as a Citizen menu.  LINK-CLASS goes on each link."
  (let* ((id (plist-get menu :id))
         (label (org-wiki--esc (plist-get menu :label)))
         (links (plist-get menu :links)))
    (concat
     (format "<nav id=\"p-%s\" class=\"citizen-menu mw-portlet mw-portlet-%s%s\" aria-label=\"%s\">\n"
             id id (if links "" " emptyPortlet") label)
     (format "\t<div class=\"citizen-menu__heading\">%s</div>\n" label)
     "\t<div class=\"citizen-menu__content\">\n"
     "\t\t<ul class=\"citizen-menu__content-list\">\n"
     (mapconcat (lambda (l) (concat "\t\t\t" (org-wiki-citizen--item l link-class) "\n"))
                links "")
     "\t\t</ul>\n"
     "\t</div>\n"
     "</nav>\n")))

(defun org-wiki-citizen--dropdown (class summary-title summary-icon card-id card
                                         &optional details-id)
  "Render one of Citizen's <details> dropdowns.
CLASS goes on the wrapper, SUMMARY-TITLE and SUMMARY-ICON make the button,
and CARD, the HTML of the card, is given the id CARD-ID.  DETAILS-ID, if
given, is the id of the <details> element."
  (concat
   (format "<div class=\"%s citizen-header__item citizen-dropdown\">\n" class)
   (format "\t<details%s class=\"citizen-dropdown-details\">\n"
           (org-wiki--attr "id" details-id))
   (format "\t\t<summary class=\"%s\" title=\"%s\" aria-details=\"%s\">%s<span>%s</span></summary>\n"
           org-wiki-citizen--icon-button summary-title card-id summary-icon summary-title)
   "\t</details>\n"
   card
   "</div>\n"))

(defun org-wiki-citizen--logo-img (logo size &optional lazy)
  "Return the logo LOGO as an <img> SIZE pixels square.  LAZY loads it lazily."
  (if (plist-get logo :src)
      (format "<img class=\"mw-logo-icon\" src=\"%s\" alt=\"\" aria-hidden=\"true\" height=\"%d\" width=\"%d\"%s>"
              (plist-get logo :src) size size (if lazy " loading=\"lazy\"" ""))
    ""))

(defun org-wiki-citizen--search (search)
  "Render SEARCH, the search plist, as Citizen's search dropdown."
  (let ((site (org-wiki--esc (plist-get search :sitename))))
    (org-wiki-citizen--dropdown
     "citizen-search" "Toggle search" org-wiki-citizen--search-svg
     "citizen-search__card"
     (concat
      "\t<div role=\"search\" id=\"citizen-search__card\" class=\"citizen-search-box citizen-search__card citizen-menu__card\">\n"
      "\t\t<div class=\"citizen-menu__card-content\">\n"
      (format "\t\t\t<form action=\"%s\" class=\"citizen-search__form\" id=\"searchform\" autocomplete=\"off\">\n"
              (org-wiki--esc (plist-get search :action)))
      (mapconcat (lambda (field)
                   (format "\t\t\t\t<input type=\"hidden\" name=\"%s\" value=\"%s\">\n"
                           (org-wiki--esc (car field)) (org-wiki--esc (cdr field))))
                 (plist-get search :fields) "")
      "\t\t\t\t<label class=\"citizen-search__formIcon\" for=\"searchInput\">"
      "<span class=\"citizen-search__icon citizen-ui-icon mw-ui-icon-wikimedia-search\"></span>"
      "<span class=\"screen-reader-text\">Search</span></label>\n"
      (format (concat "\t\t\t\t<input type=\"search\" name=\"%s\" placeholder=\"Search %s\""
                      " aria-label=\"Search %s\" autocapitalize=\"none\" spellcheck=\"false\""
                      " title=\"Search %s [f]\" accesskey=\"f\" id=\"searchInput\">\n")
              (org-wiki--esc (plist-get search :name)) site site site)
      "\t\t\t</form>\n"
      "\t\t</div>\n"
      "\t</div>\n")
     "citizen-search-details")))

(defun org-wiki-citizen--drawer (page)
  "Render the drawer, Citizen's home for the sidebar, from PAGE."
  (let ((logo (plist-get page :logo))
        (site (org-wiki--esc (plist-get (plist-get page :search) :sitename))))
    (org-wiki-citizen--dropdown
     "citizen-drawer" "Toggle menu" org-wiki-citizen--menu-svg
     "citizen-drawer__card"
     (concat
      "\t<div id=\"citizen-drawer__card\" class=\"citizen-drawer__card citizen-menu__card\">\n"
      "\t\t<div class=\"citizen-menu__card-content\">\n"
      "\t\t\t<div class=\"citizen-drawer__header\">\n"
      (format "\t\t\t\t<a href=\"%s\" class=\"mw-logo citizen-drawer__logo\" title=\"Visit the main page\">%s</a>\n"
              (org-wiki--esc (plist-get logo :href))
              (org-wiki-citizen--logo-img logo 80 t))
      "\t\t\t\t<div class=\"citizen-drawer__siteinfo\">"
      (format "<div class=\"mw-logo-wordmark\">%s</div></div>\n" site)
      "\t\t\t</div>\n"
      "\t\t\t<section id=\"citizen-main-menu\" class=\"citizen-main-menu citizen-drawer__menu\">\n"
      (mapconcat #'org-wiki-citizen--menu (plist-get page :sidebar) "")
      "\t\t\t</section>\n"
      "\t\t</div>\n"
      "\t</div>\n"))))

(defun org-wiki-citizen--user-menu (page)
  "Render the personal menu from PAGE."
  (org-wiki-citizen--dropdown
   "citizen-userMenu" "Toggle personal menu"
   "<span class=\"citizen-ui-icon mw-ui-icon-wikimedia-userAvatar\"></span>"
   "citizen-userMenu__card"
   (concat
    "\t<div id=\"citizen-userMenu__card\" class=\"citizen-menu__card\">\n"
    "\t\t<div class=\"citizen-menu__card-content\">\n"
    (org-wiki-citizen--menu (plist-get page :personal))
    "\t\t</div>\n"
    "\t</div>\n")))

(defun org-wiki-citizen--header (page)
  "Render Citizen's header rail from PAGE."
  (let ((logo (plist-get page :logo)))
    (concat
     "<header class=\"mw-header citizen-header\">\n"
     "<div class=\"citizen-header__logo\">\n"
     (format "\t<a href=\"%s\" class=\"mw-logo citizen-cdx-button--size-large %s cdx-button--icon-only cdx-button--weight-quiet\" title=\"Visit the main page\">%s%s</a>\n"
             (org-wiki--esc (plist-get logo :href))
             org-wiki-citizen--button
             (org-wiki-citizen--logo-img logo 32)
             (org-wiki-citizen--icon "home"))
     "</div>\n"
     (org-wiki-citizen--search (plist-get page :search))
     (org-wiki-citizen--drawer page)
     "<div class=\"citizen-header__inner\">\n"
     "\t<div class=\"citizen-header__start\"></div>\n"
     "\t<div class=\"citizen-header__end\">\n"
     (org-wiki-citizen--user-menu page)
     "\t</div>\n"
     "</div>\n"
     "</header>\n")))

(defun org-wiki-citizen--page-header (page)
  "Render the title, the tagline and the page tabs from PAGE."
  (let ((tab-class (concat "citizen-cdx-button--size-large " org-wiki-citizen--button
                           " cdx-button--weight-quiet")))
    (concat
     "<header class=\"mw-body-header citizen-page-header\" id=\"citizen-page-header\">\n"
     "<div class=\"citizen-page-header-inner\">\n"
     "\t<div class=\"citizen-page-heading\">\n"
     "\t\t<div class=\"firstHeading-container\">\n"
     (format (concat "\t\t\t<h1 id=\"firstHeading\" class=\"firstHeading mw-first-heading\">"
                     "<span class=\"mw-page-title-main\">%s</span></h1>\n")
             (plist-get page :title))
     "\t\t\t<div class=\"mw-indicators\"></div>\n"
     "\t\t</div>\n"
     (format "\t\t<div id=\"siteSub\">%s</div>\n" (org-wiki--esc (plist-get page :tagline)))
     "\t</div>\n"
     "\t<div class=\"citizen-page-actions\">\n"
     "\t\t<div class=\"citizen-page-actions__tabs\">\n"
     (org-wiki-citizen--menu (plist-get page :action-tabs) tab-class)
     (org-wiki-citizen--menu
      (org-combine-plists (plist-get page :namespace-tabs)
                          '(:id "associated-pages" :label "Related pages"))
      tab-class)
     "\t\t</div>\n"
     "\t</div>\n"
     "</div>\n"
     "</header>\n")))

(defun org-wiki-citizen--toc-tree (entries)
  "Nest ENTRIES, a flat list from `org-wiki--toc-entries', by level.
Return a list of (ENTRY . CHILDREN)."
  (let (tree)
    (while entries
      (let* ((entry (pop entries))
             (level (plist-get entry :level))
             children)
        (while (and entries (> (plist-get (car entries) :level) level))
          (push (pop entries) children))
        (push (cons entry (org-wiki-citizen--toc-tree (nreverse children))) tree)))
    (nreverse tree)))

(defun org-wiki-citizen--toc-line (node depth)
  "Render NODE, an (ENTRY . CHILDREN) pair, as a TOC line DEPTH deep.
Follows templates/TableOfContents__line.mustache."
  (let* ((entry (car node))
         (id (plist-get entry :id)))
    (concat
     (format "<li id=\"toc-%s\" class=\"citizen-toc-list-item citizen-toc-level-%d\">" id depth)
     (format "<a class=\"citizen-toc-link citizen-page-aside__link %s cdx-button--weight-quiet\" href=\"#%s\" role=\"button\">"
             org-wiki-citizen--button id)
     "<div class=\"citizen-toc-content\"><div class=\"citizen-toc-text\">"
     (format "<span class=\"citizen-toc-numb\">%s</span> " (plist-get entry :number))
     (format "<span class=\"citizen-toc-heading\">%s</span>" (plist-get entry :text))
     "</div></div></a>"
     (format "<ul id=\"toc-%s-sublist\" class=\"citizen-toc-list\">" id)
     (mapconcat (lambda (child) (org-wiki-citizen--toc-line child (1+ depth)))
                (cdr node) "")
     "</ul></li>\n")))

(defun org-wiki-citizen--aside (page)
  "Render the side column, with PAGE's table of contents, or nil if it has none."
  (let ((toc (plist-get page :toc)))
    (when toc
      (concat
       "<aside class=\"citizen-page-aside\" aria-label=\"Side column\">\n"
       "<div class=\"citizen-page-aside__sticky\">\n"
       "<nav id=\"citizen-toc\" class=\"citizen-toc citizen-dropdown citizen-page-aside__panel citizen-page-aside__panel--toc\""
       " aria-labelledby=\"citizen-page-aside-toc-heading\">\n"
       (format "\t<div id=\"citizen-page-aside-toc-heading\" class=\"citizen-page-aside__heading\">%s</div>\n"
               (org-wiki--esc org-wiki-toc-title))
       "\t<details class=\"citizen-dropdown-details\">\n"
       (format "\t\t<summary class=\"citizen-dropdown-summary\" title=\"%s\" aria-details=\"mw-panel-toc\">%s<span>%s</span></summary>\n"
               (org-wiki--esc org-wiki-toc-title)
               (org-wiki-citizen--icon "listBullet")
               (org-wiki--esc org-wiki-toc-title))
       "\t</details>\n"
       "\t<div id=\"mw-panel-toc\" class=\"citizen-page-aside__body citizen-toc-card citizen-menu__card\">\n"
       "\t\t<div class=\"citizen-menu__card-content\">\n"
       (format "\t\t\t<a class=\"citizen-toc-top citizen-toc-link citizen-page-aside__link %s cdx-button--weight-quiet\" title=\"Back to top\" href=\"#top\" role=\"button\">%s<div class=\"citizen-toc-text\">Back to top</div></a>\n"
               org-wiki-citizen--button (org-wiki-citizen--icon "arrowUp" "div"))
       "\t\t\t<div class=\"citizen-toc-contents\" id=\"mw-panel-toc-list\">\n"
       "\t\t\t\t<div class=\"citizen-toc-indicator\"></div>\n"
       "\t\t\t\t<ul class=\"citizen-toc-list\">\n"
       (mapconcat (lambda (node) (org-wiki-citizen--toc-line node 1))
                  (org-wiki-citizen--toc-tree toc) "")
       "\t\t\t\t</ul>\n"
       "\t\t\t</div>\n"
       "\t\t</div>\n"
       "\t</div>\n"
       "</nav>\n"
       "</div>\n"
       "</aside>\n"))))

(defun org-wiki-citizen--page-footer (page)
  "Render the box under the article: PAGE's footer lines, as Citizen's page info."
  (concat
   "<footer class=\"citizen-page-footer\">\n"
   "<div class=\"page-info\">\n"
   (mapconcat (lambda (line)
                (format "\t<section class=\"page-info__item\"><div class=\"page-info__text\">%s</div></section>\n"
                        line))
              (plist-get page :footer-info) "")
   "</div>\n"
   "</footer>\n"))

(defun org-wiki-citizen--footer (page)
  "Render the site footer from PAGE."
  (let ((logo (plist-get page :logo)))
    (concat
     "<footer class=\"mw-footer citizen-footer\">\n"
     "<div class=\"citizen-footer__container\">\n"
     "\t<section class=\"citizen-footer__content\">\n"
     "\t\t<div class=\"citizen-footer__siteinfo\">\n"
     (format "\t\t\t<div id=\"footer-sitetitle\" class=\"citizen-footer__sitetitle mw-wiki-title\">%s<div class=\"mw-logo-wordmark\">%s</div></div>\n"
             (org-wiki-citizen--logo-img logo 48 t)
             (org-wiki--esc (plist-get (plist-get page :search) :sitename)))
     (format "\t\t\t<p id=\"footer-desc\" class=\"citizen-footer__desc\">%s</p>\n"
             (org-wiki--esc (plist-get page :tagline)))
     "\t\t</div>\n"
     "\t\t<nav id=\"footer-places\">\n\t\t\t<ul>\n"
     (mapconcat
      (lambda (l)
        (format "\t\t\t\t<li%s><a%s>%s</a></li>\n"
                (org-wiki--attr "id" (plist-get l :id))
                (org-wiki--attr "href" (or (plist-get l :href) "#"))
                (org-wiki--esc (plist-get l :text))))
      (plist-get page :footer-places) "")
     "\t\t\t</ul>\n\t\t</nav>\n"
     "\t</section>\n"
     "\t<section class=\"citizen-footer__bottom\">\n"
     "\t\t<nav id=\"footer-icons\" class=\"noprint\">\n\t\t\t<ul>\n"
     (mapconcat
      (lambda (b)
        (format "\t\t\t\t<li>%s<img src=\"%s\" alt=\"%s\" height=\"31\" loading=\"lazy\">%s</li>\n"
                (if (plist-get b :href)
                    (format "<a href=\"%s\" class=\"%s cdx-button--size-large\">"
                            (org-wiki--esc (plist-get b :href)) org-wiki-citizen--button)
                  "")
                (plist-get b :src)
                (org-wiki--esc (plist-get b :alt))
                (if (plist-get b :href) "</a>" "")))
      (plist-get page :footer-buttons) "")
     "\t\t\t</ul>\n\t\t</nav>\n"
     "\t</section>\n"
     "</div>\n"
     "</footer>\n")))

(defun org-wiki-citizen-page (page)
  "Render PAGE, the page plist, as a Citizen document body."
  (let ((aside (org-wiki-citizen--aside page)))
    (concat
     (format "<body class=\"%s%s skin--responsive\">\n"
             (if aside "citizen-page-aside-enabled " "")
             (org-wiki-body-class page))
     "<a class=\"mw-jump-link citizen-jump-link\" href=\"#bodyContent\">Jump to content</a>\n"
     (org-wiki-citizen--header page)
     "<div class=\"citizen-page-container\">\n"
     "<div class=\"citizen-sitenotice-container\"><div id=\"siteNotice\"></div></div>\n"
     "<main class=\"mw-body\" id=\"content\">\n"
     "<a id=\"top\"></a>\n"
     (org-wiki-citizen--page-header page)
     "<div class=\"citizen-body-container\">\n"
     "<div id=\"bodyContent\" class=\"citizen-body\">\n"
     (format "\t<div id=\"contentSub\"><div id=\"mw-content-subtitle\">%s</div></div>\n"
             (or (plist-get page :subtitle) ""))
     (format "\t<div id=\"mw-content-text\" class=\"mw-body-content mw-content-ltr\" lang=\"%s\" dir=\"ltr\">\n"
             (org-wiki--esc (plist-get page :lang)))
     (plist-get page :content)
     "\t</div>\n"
     "</div>\n"
     (or aside "")
     (org-wiki-citizen--page-footer page)
     "</div>\n"
     "</main>\n"
     (org-wiki-citizen--footer page)
     "</div>\n"
     "</body>\n")))

(org-wiki-define-skin 'citizen
  :title "Citizen"
  :stylesheets '("css/citizen.css")
  :body-class "skin-citizen"
  :html-class (concat "skin-theme-clientpref-os citizen-v4"
                      " citizen-header-position-left citizen-header-position-mobile-bottom"
                      " citizen-feature-autohide-navigation-clientpref-0"
                      " citizen-feature-image-dimming-clientpref-0"
                      " citizen-feature-pure-black-clientpref-0"
                      " citizen-feature-custom-font-size-clientpref-standard"
                      " citizen-feature-custom-width-clientpref-standard"
                      " citizen-feature-performance-mode-clientpref-1")
  :own-toc t
  :credit (concat "Presentation adapted from the Citizen skin, which is"
                 " copyright the Citizen contributors and licensed"
                 " GPL-3.0-or-later.")
  :page #'org-wiki-citizen-page)

(provide 'ox-wiki-skin-citizen)

;;; ox-wiki-skin-citizen.el ends here
