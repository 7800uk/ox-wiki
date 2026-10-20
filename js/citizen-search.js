/*
 * citizen-search.js -- what Citizen's search shortcuts open, without a wiki.
 *
 * On a wiki, "/", Ctrl+K and the search button open Citizen's command palette,
 * skins.citizen.commandPalette: a Vue app that searches the wiki's own API as
 * you type.  An exported page has no API to search, and its search box posts
 * to an outside engine instead (`org-wiki-search-action').  So this module
 * takes the palette's name and its interface -- initApp( overlay, { onClose } )
 * returning open, close and focus -- and opens the search card the skin
 * already renders.
 *
 * The search button itself stays a plain <details> toggle: the skin leaves the
 * id off its <summary> that the palette's own setup looks for, so that setup
 * steps aside rather than removing the card.  Only the keyboard shortcuts come
 * through here.
 *
 * Hand-written, like js/mediawiki.js, which must be loaded first.
 */

mw.loader.impl( () => [ 'skins.citizen.commandPalette', {
	main: 'index.js',
	files: {
		'index.js': function ( require, module ) {
			function initApp( overlay, { onClose } ) {
				const details = document.getElementById( 'citizen-search-details' );
				const input = document.getElementById( 'searchInput' );

				function close() {
					if ( details ) {
						details.open = false;
					}
					onClose();
				}

				if ( input ) {
					input.addEventListener( 'keydown', ( event ) => {
						if ( event.key === 'Escape' ) {
							close();
						}
					} );
				}

				function open( prefill ) {
					if ( details ) {
						details.open = true;
					}
					if ( input ) {
						if ( typeof prefill === 'string' ) {
							input.value = prefill;
						}
						input.focus();
						input.select();
					}
				}

				// The palette asks only for focus when it thinks it is
				// still open, but the card may have been closed since by a
				// click outside it, which the palette never hears about.
				return { open, close, focus: () => open( null ) };
			}

			module.exports = { initApp };
		}
	}
} ] );
