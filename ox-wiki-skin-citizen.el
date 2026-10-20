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
;; So are its scripts, in js/citizen.js, and they run on js/mediawiki.js, a
;; small stand-in for the client runtime a wiki provides.  They bring the
;; preferences panel, the share dialog, the sticky header, collapsible
;; sections, the scroll-tracking of the contents and the folding of the page
;; tabs on narrow screens.  The one piece that needs a wiki behind it, the
;; command palette, is replaced by js/citizen-search.js, which opens the
;; search box instead.  Without JavaScript the page still works: Citizen's
;; menus are <details> elements its stylesheet opens and closes.
;;
;; Beyond Vector and MonoBook, it draws the table of contents itself, in the
;; side column, so it asks for `:own-toc' and builds the list from the page
;; plist's `:toc'; it themes from classes on <html>, starting from
;; `skin-theme-clientpref-os' so the page follows the reader's light or dark
;; setting until they pick one; and it reshapes Org's outline into the
;; <section> markup Citizen collapses, the way Citizen's own PHP does for a
;; wiki's parser output.
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
    ("ca-viewsource" . "editLock")
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

(defconst org-wiki-citizen--sticky-buttons
  '(("citizen-share-sticky-header" "#citizen-share" "share")
    ("ca-view-sticky-header" "#ca-view > a" "eye")
    ("ca-subject-sticky-header" "[id^='ca-nstab-']:not(.selected) > a" "article")
    ("ca-history-sticky-header" "#ca-history > a" "history")
    ("ca-viewsource-sticky-header" "#ca-viewsource > a" "editLock")
    ("ca-pdf-sticky-header" "#ca-pdf > a" "printer"))
  "The sticky header's buttons: (ID CLICK-TARGET ICON).
Each stands in for the element CLICK-TARGET selects, and Citizen's script
removes any whose target the page does not have, so the list can name every
tab ox-wiki might draw.")

(defconst org-wiki-citizen--tools-ids '("tb" "tools")
  "Sidebar menus that are the page tools.
Citizen keeps these in the page's More menu rather than in the drawer.")

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

(cl-defun org-wiki-citizen--dropdown (&key class id details-id title icon card-id card)
  "Render one of Citizen's <details> dropdowns.
CLASS goes on the wrapper, which ID names; DETAILS-ID names the <details>.
TITLE and ICON make the button, and CARD, the HTML of the card, is the
element CARD-ID names."
  (concat
   (format "<div%s class=\"%s citizen-dropdown\">\n" (org-wiki--attr "id" id) class)
   (format "\t<details%s class=\"citizen-dropdown-details\">\n"
           (org-wiki--attr "id" details-id))
   (format "\t\t<summary class=\"%s\" title=\"%s\" aria-details=\"%s\">%s<span>%s</span></summary>\n"
           org-wiki-citizen--icon-button title card-id icon title)
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
  "Render SEARCH, the search plist, as Citizen's search dropdown.
The <summary> deliberately has no id: Citizen's command palette looks for
`citizen-search-summary' to take the button over, and without a wiki to
search it should leave the button and its card alone.  See
js/citizen-search.js."
  (let ((site (org-wiki--esc (plist-get search :sitename))))
    (org-wiki-citizen--dropdown
     :class "citizen-search citizen-header__item"
     :details-id "citizen-search-details"
     :title "Toggle search" :icon org-wiki-citizen--search-svg
     :card-id "citizen-search__card"
     :card
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
      "\t</div>\n"))))

(defun org-wiki-citizen--tools-p (menu)
  "Non-nil if MENU is the page tools, which Citizen puts in the More menu."
  (member (plist-get menu :id) org-wiki-citizen--tools-ids))

(defun org-wiki-citizen--drawer (page)
  "Render the drawer, Citizen's home for the sidebar, from PAGE."
  (let ((logo (plist-get page :logo))
        (site (org-wiki--esc (plist-get (plist-get page :search) :sitename))))
    (org-wiki-citizen--dropdown
     :class "citizen-drawer citizen-header__item"
     :title "Toggle menu" :icon org-wiki-citizen--menu-svg
     :card-id "citizen-drawer__card"
     :card
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
      (mapconcat #'org-wiki-citizen--menu
                 (seq-remove #'org-wiki-citizen--tools-p (plist-get page :sidebar))
                 "")
      "\t\t\t</section>\n"
      "\t\t</div>\n"
      "\t</div>\n"))))

(defun org-wiki-citizen--preferences ()
  "Render the preferences dropdown, which Citizen's script fills in.
Until it does, the card shows Citizen's loading skeleton."
  (let ((row (concat "<div class=\"citizen-preferences-skeleton__row\">"
                     "<div class=\"citizen-preferences-skeleton__label\"></div>"
                     "<div class=\"citizen-preferences-skeleton__description\"></div></div>"))
        (heading "<div class=\"citizen-preferences-skeleton__heading\"></div>"))
    (org-wiki-citizen--dropdown
     :class "citizen-preferences-dropdown citizen-header__item"
     :details-id "citizen-preferences-details"
     :title "Toggle preferences menu"
     :icon (org-wiki-citizen--icon "configure")
     :card-id "citizen-preferences-dropdown__card"
     :card
     (concat
      "\t<div id=\"citizen-preferences-dropdown__card\" class=\"citizen-menu__card\">\n"
      "\t\t<div class=\"citizen-menu__card-content\">\n"
      "\t\t\t<div id=\"citizen-preferences-content\" class=\"citizen-preferences\">\n"
      "\t\t\t\t<div class=\"citizen-preferences-skeleton\" role=\"status\" aria-busy=\"true\" aria-live=\"polite\">"
      heading row row row heading row row
      "</div>\n"
      "\t\t\t\t<div class=\"citizen-preferences-error\" role=\"alert\" hidden>"
      "<p class=\"citizen-preferences-error__message\">Couldn't load preferences.</p>"
      "<button class=\"cdx-button citizen-preferences-error__retry\" type=\"button\">Retry</button>"
      "</div>\n"
      "\t\t\t</div>\n"
      "\t\t</div>\n"
      "\t</div>\n"))))

(defun org-wiki-citizen--user-menu (page)
  "Render the personal menu from PAGE."
  (org-wiki-citizen--dropdown
   :class "citizen-userMenu citizen-header__item"
   :title "Toggle personal menu"
   :icon (org-wiki-citizen--icon "userAvatar")
   :card-id "citizen-userMenu__card"
   :card
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
     (org-wiki-citizen--preferences)
     (org-wiki-citizen--user-menu page)
     "\t</div>\n"
     "</div>\n"
     "</header>\n")))

(defun org-wiki-citizen--share ()
  "Render the share button, and the dialog Citizen's script opens from it."
  (concat
   "<div class=\"citizen-share-trigger citizen-header__item\">\n"
   "\t<button type=\"button\" id=\"citizen-share\" class=\"citizen-share citizen-cdx-button--size-large cdx-button cdx-button--weight-quiet cdx-button--icon-only\""
   " title=\"Share this page\" aria-label=\"Share this page\" aria-haspopup=\"dialog\">"
   (org-wiki-citizen--icon "share") "<span>Share this page</span></button>\n"
   "\t<dialog id=\"citizen-share-dialog\" class=\"citizen-share-dialog\" aria-label=\"Share this page\">"
   "<div id=\"citizen-share-dialog-content\" class=\"citizen-share-dialog__content\">"
   "<div class=\"citizen-share-skeleton\" role=\"status\" aria-busy=\"true\" aria-live=\"polite\">"
   "<div class=\"citizen-share-skeleton__bar citizen-share-skeleton__bar--short\"></div>"
   "<div class=\"citizen-share-skeleton__bar citizen-share-skeleton__bar--wide\"></div>"
   "<div class=\"citizen-share-skeleton__bar citizen-share-skeleton__bar--medium\"></div>"
   "</div></div></dialog>\n"
   "</div>\n"))

(defun org-wiki-citizen--more (page)
  "Render the page's More menu: the page tools from PAGE's sidebar.
On a narrow screen Citizen's script also folds the tabs into it."
  (org-wiki-citizen--dropdown
   :class "citizen-page-actions-more citizen-page-actions__item"
   :id "citizen-page-more-dropdown"
   :title "More actions"
   :icon (org-wiki-citizen--icon "ellipsis")
   :card-id "citizen-page-actions-more__card"
   :card
   (concat
    "\t<div id=\"citizen-page-actions-more__card\" class=\"citizen-menu__card\">\n"
    "\t\t<div class=\"citizen-menu__card-content\">\n"
    (org-wiki-citizen--menu '(:id "cactions" :label "More"))
    (mapconcat (lambda (menu)
                 (org-wiki-citizen--menu (org-combine-plists menu '(:id "tb"))))
               (seq-filter #'org-wiki-citizen--tools-p (plist-get page :sidebar))
               "")
    "\t\t</div>\n"
    "\t</div>\n")))

(defun org-wiki-citizen--page-header (page)
  "Render the title, the tagline and the page actions from PAGE."
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
     (org-wiki-citizen--share)
     "\t\t<div class=\"citizen-page-actions__tabs\">\n"
     (org-wiki-citizen--menu (plist-get page :action-tabs) tab-class)
     (org-wiki-citizen--menu
      (org-combine-plists (plist-get page :namespace-tabs)
                          '(:id "associated-pages" :label "Related pages"))
      tab-class)
     "\t\t</div>\n"
     (org-wiki-citizen--more page)
     "\t</div>\n"
     "</div>\n"
     "</header>\n"
     "<div id=\"citizen-page-header-sticky-sentinel\"></div>\n")))

(defun org-wiki-citizen--sections (html)
  "Give HTML, the article, the section markup Citizen collapses.
Org wraps each heading and what follows it in a div.outline-N, which is
already the right tree; Citizen wants it as <section class=\"citizen-section\">
with the heading in a div.mw-heading, which is what its PHP makes of a
wiki's parser output.  Each outline div becomes a section, closed where the
div closed, and its heading is wrapped."
  (with-temp-buffer
    (insert html)
    (goto-char (point-min))
    (let (stack)
      (while (re-search-forward "<\\(/?\\)div\\(\\s-[^>]*\\)?>" nil t)
        (cond
         ((string= (match-string 1) "/")
          (when (pop stack)
            (replace-match "</section>" t t)))
         ((string-match-p "\\`[^>]*\\bid=\"outline-container-" (or (match-string 2) ""))
          (push t stack)
          (replace-match
           (concat "<section"
                   (save-match-data
                     (replace-regexp-in-string
                      "class=\"\\([^\"]*\\)\"" "class=\"\\1 citizen-section\""
                      (match-string 2) t))
                   ">")
           t t)
          (when (looking-at "\\s-*\\(<h\\([1-6]\\)[ >]\\(?:.\\|\n\\)*?</h\\2>\\)")
            (replace-match
             (format "<div class=\"mw-heading mw-heading%s citizen-section-heading\">%s</div>"
                     (match-string 2) (match-string 1))
             t t nil 1)))
         (t (push nil stack)))))
    (buffer-string)))

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
Follows templates/TableOfContents__line.mustache, toggle button included."
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
     (when (and (= depth 1) (cdr node))
       (format (concat "<button aria-controls=\"toc-%s-sublist\" class=\"citizen-toc-toggle"
                       " cdx-button cdx-button--weight-quiet cdx-button--icon-only"
                       " cdx-button--size-medium\">%s<span>Toggle %s subsection</span></button>")
               id (org-wiki-citizen--icon "collapse")
               (org-wiki--esc (org-wiki--untag (plist-get entry :text)))))
     (format "<ul id=\"toc-%s-sublist\" class=\"citizen-toc-list\">" id)
     (mapconcat (lambda (child) (org-wiki-citizen--toc-line child (1+ depth)))
                (cdr node) "")
     "</ul></li>\n")))

(defun org-wiki-citizen--toc (toc)
  "Render TOC, from the page plist, as Citizen's contents panel."
  (concat
   "<nav id=\"citizen-toc\" class=\"citizen-toc citizen-dropdown citizen-page-aside__panel citizen-page-aside__panel--toc\""
   " aria-labelledby=\"citizen-page-aside-toc-heading\" data-order=\"20\">\n"
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
   "</nav>\n"))

(defun org-wiki-citizen--last-modified (page)
  "Render the side column's Last modified panel from PAGE.
It links to the history page when the page has one, as Citizen links to
the latest diff; Citizen's script rewrites the date as \"3 days ago\"."
  (let* ((time (plist-get page :modified))
         (history (seq-find (lambda (l) (equal (plist-get l :id) "ca-history"))
                            (plist-get (plist-get page :action-tabs) :links)))
         (tag (if history "a" "span")))
    (concat
     "<div id=\"citizen-page-aside-lastmod\" class=\"citizen-page-aside__panel citizen-page-aside__panel--lastmod\" data-order=\"10\">\n"
     "\t<div id=\"citizen-page-aside-lastmod-heading\" class=\"citizen-page-aside__heading\">Last modified</div>\n"
     "\t<div class=\"citizen-page-aside__body\">"
     (format "<%s class=\"citizen-page-aside__link %s cdx-button--weight-quiet\"%s title=\"%s\">"
             tag org-wiki-citizen--button
             (if history (org-wiki--attr "href" (plist-get history :href)) "")
             (org-wiki--esc (format-time-string "This page was last edited on %e %B %Y, at %H:%M." time)))
     (org-wiki-citizen--icon "history")
     (format "<time id=\"citizen-page-aside-lastmod-time\" datetime=\"%s\">%s</time>"
             (format-time-string "%FT%TZ" time t)
             (string-trim (format-time-string "%e %B %Y" time)))
     (format "</%s></div>\n" tag)
     "</div>\n")))

(defun org-wiki-citizen--aside (page)
  "Render the side column from PAGE: when it was edited, and its contents."
  (let ((toc (plist-get page :toc)))
    (concat
     "<aside class=\"citizen-page-aside\" aria-label=\"Side column\">\n"
     (org-wiki-citizen--last-modified page)
     "<div class=\"citizen-page-aside__sticky\">\n"
     (if toc (org-wiki-citizen--toc toc) "")
     "</div>\n"
     "</aside>\n")))

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

(defun org-wiki-citizen--sticky-header (page)
  "Render the bar Citizen's script shows once PAGE's title scrolls away.
Follows templates/StickyHeader.mustache."
  (concat
   "<div class=\"citizen-sticky-header-container\">\n"
   "<div id=\"citizen-sticky-header\" class=\"citizen-sticky-header\">\n"
   "\t<div class=\"citizen-sticky-header-background\"></div>\n"
   "\t<div class=\"citizen-sticky-header-inner\">\n"
   "\t\t<div class=\"citizen-sticky-header-start\">"
   (format "<a href=\"#top\" title=\"Back to top\" class=\"citizen-sticky-header-backtotop %s cdx-button--size-large cdx-button--weight-quiet\" tabindex=\"-1\" aria-hidden=\"true\">"
           org-wiki-citizen--button)
   (org-wiki-citizen--icon "arrowUp" "div")
   "<div class=\"citizen-sticky-header-page-info\">"
   (format "<div class=\"citizen-sticky-header-page-title\"><span class=\"mw-page-title-main\">%s</span></div>"
           (plist-get page :title))
   (format "<div class=\"citizen-sticky-header-page-tagline\">%s</div>"
           (org-wiki--esc (plist-get page :tagline)))
   "</div></a></div>\n"
   "\t\t<div class=\"citizen-sticky-header-end\" aria-hidden=\"true\">\n"
   (mapconcat
    (lambda (button)
      (cl-destructuring-bind (id target icon) button
        (format (concat "\t\t\t<button class=\"cdx-button cdx-button--weight-quiet cdx-button--action-default"
                        " cdx-button--size-large cdx-button--icon-only\" id=\"%s\" tabindex=\"-1\""
                        " data-mw-citizen-click-target=\"%s\">%s<span></span></button>\n")
                id (org-wiki--esc target) (org-wiki-citizen--icon icon))))
    org-wiki-citizen--sticky-buttons "")
   "\t\t\t<div id=\"citizen-sticky-header-more\" class=\"citizen-sticky-header-dropdown-container\"></div>\n"
   "\t\t</div>\n"
   "\t</div>\n"
   "</div>\n"
   "</div>\n"))

(defun org-wiki-citizen-page (page)
  "Render PAGE, the page plist, as a Citizen document body."
  (concat
   (format "<body class=\"citizen-page-aside-enabled citizen-sections-enabled %s skin--responsive\">\n"
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
   (org-wiki-citizen--sections (plist-get page :content))
   "\t</div>\n"
   "</div>\n"
   (org-wiki-citizen--aside page)
   (org-wiki-citizen--page-footer page)
   "</div>\n"
   "</main>\n"
   (org-wiki-citizen--footer page)
   "</div>\n"
   (org-wiki-citizen--sticky-header page)
   "</body>\n"))

(org-wiki-define-skin 'citizen
  :title "Citizen"
  :stylesheets '("css/citizen.css")
  :scripts '("js/mediawiki.js" "js/citizen.js" "js/citizen-search.js")
  :modules '("skins.citizen.scripts")
  :body-class "skin-citizen"
  :html-class (concat "skin-theme-clientpref-os citizen-v4"
                      " citizen-header-position-left citizen-header-position-mobile-bottom"
                      " citizen-feature-autohide-navigation-clientpref-1"
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
