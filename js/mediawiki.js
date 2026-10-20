/*
 * mediawiki.js -- just enough of MediaWiki's client runtime to run a skin's
 * ResourceLoader modules in a page no wiki served.
 *
 * A skin's scripts are vendored exactly as ResourceLoader serves them: a run of
 * mw.loader.impl() calls, each handing over a module's files, styles and
 * messages.  On a wiki those land in the `mw' that the startup module and
 * mediawiki.base define, which also fetch further modules from load.php.  An
 * exported page has no load.php to ask, so this file stands in for both: every
 * module the page will use is already in it, and a module runs when something
 * first asks for it, the way mw.loader would once the request came back.
 *
 * It is the only hand-written script, the counterpart of css/org-wiki.css, and
 * it covers only the part of the `mw' API that the vendored modules call.  What
 * needs a wiki behind it says so instead of pretending: mw.Api rejects, and
 * mw.template has no compilers.  No module here needs jQuery, so there is none.
 *
 * Load it before the modules, in <head>: it also does the two jobs MediaWiki's
 * inline head script does before the first paint -- swapping `client-nojs' for
 * `client-js' and applying the client preferences saved by an earlier visit.
 */

( function () {
	'use strict';

	const html = document.documentElement;

	html.className = html.className.replace( /(^|\s)client-nojs(\s|$)/, '$1client-js$2' );

	/* --------------------------------------------------------- Storage */

	function SafeStorage( getStore ) {
		this.getStore = getStore;
	}

	SafeStorage.prototype = {
		get( key ) {
			try {
				return this.getStore().getItem( key );
			} catch ( e ) {
				return false;
			}
		},
		set( key, value ) {
			try {
				this.getStore().setItem( key, value );
				return true;
			} catch ( e ) {
				return false;
			}
		},
		remove( key ) {
			try {
				this.getStore().removeItem( key );
				return true;
			} catch ( e ) {
				return false;
			}
		},
		getObject( key ) {
			const json = this.get( key );
			if ( json === false ) {
				return false;
			}
			try {
				return JSON.parse( json );
			} catch ( e ) {
				return null;
			}
		},
		setObject( key, value ) {
			let json;
			try {
				json = JSON.stringify( value );
			} catch ( e ) {
				return false;
			}
			return this.set( key, json );
		}
	};

	const storage = new SafeStorage( () => window.localStorage );
	storage.session = new SafeStorage( () => window.sessionStorage );

	/* MediaWiki's inline head script, which reapplies saved client
	   preferences (theme, font size, page width) before anything paints. */
	( function applyClientPrefs() {
		const saved = storage.get( 'mwclientpreferences' );
		if ( !saved ) {
			return;
		}
		let className = html.className;
		saved.split( ',' ).forEach( ( pref ) => {
			const pattern = new RegExp(
				'(^| )' + pref.replace( /-clientpref-\w+$|[^\w-]+/g, '' ) + '-clientpref-\\w+( |$)'
			);
			if ( pattern.test( className ) ) {
				className = className.replace( pattern, '$1' + pref + '$2' );
			} else {
				className += ' ' + pref;
			}
		} );
		html.className = className;
	}() );

	/* ---------------------------------------------------- mw.Map, mw.config */

	function MwMap( values ) {
		this.values = values || Object.create( null );
	}

	MwMap.prototype = {
		get( selection, fallback ) {
			if ( fallback === undefined ) {
				fallback = null;
			}
			if ( Array.isArray( selection ) ) {
				const result = {};
				selection.forEach( ( key ) => {
					result[ key ] = this.get( key, fallback );
				} );
				return result;
			}
			if ( typeof selection === 'string' ) {
				return this.exists( selection ) ? this.values[ selection ] : fallback;
			}
			if ( selection === undefined ) {
				return Object.assign( {}, this.values );
			}
			return fallback;
		},
		set( selection, value ) {
			if ( typeof selection === 'object' && selection !== null ) {
				Object.keys( selection ).forEach( ( key ) => {
					this.values[ key ] = selection[ key ];
				} );
				return true;
			}
			if ( typeof selection === 'string' && arguments.length > 1 ) {
				this.values[ selection ] = value;
				return true;
			}
			return false;
		},
		exists( key ) {
			return Object.prototype.hasOwnProperty.call( this.values, key );
		}
	};

	/* A page here is a file, not a wiki title: there is no article path to
	   prefetch along, no special namespace, and no script path to register a
	   service worker under.  Skins read these and step aside when they are
	   empty. */
	const config = new MwMap();
	config.set( {
		wgArticlePath: '',
		wgScriptPath: null,
		wgFormattedNamespaces: {},
		wgCanonicalSpecialPageName: false,
		wgNamespaceNumber: 0,
		wgAction: 'view',
		wgUserName: null,
		wgPageName: document.title,
		wgTitle: document.title
	} );

	/* ---------------------------------------------------------- Messages */

	const messages = new MwMap();

	function escapeHtml( text ) {
		return String( text ).replace( /[&<>"']/g, ( c ) => ( {
			'&': '&amp;',
			'<': '&lt;',
			'>': '&gt;',
			'"': '&quot;',
			"'": '&#039;'
		}[ c ] ) );
	}

	function Message( map, key, parameters ) {
		this.map = map;
		this.key = key;
		this.parameters = parameters || [];
	}

	Message.prototype = {
		params( parameters ) {
			this.parameters.push( ...parameters );
			return this;
		},
		/* $1-style parameters, and {{PLURAL:}} with English's two forms.
		   That is all the wikitext the vendored messages use. */
		plain() {
			if ( !this.exists() ) {
				return '⧼' + this.key + '⧽';
			}
			return String( this.map.get( this.key ) )
				.replace( /\$(\d+)/g, ( match, n ) => {
					const value = this.parameters[ n - 1 ];
					return value === undefined ? match : String( value );
				} )
				.replace( /\{\{PLURAL:\s*([^|}]*)\|([^}]*)\}\}/gi, ( match, count, forms ) => {
					const list = forms.split( '|' );
					return Number( count ) === 1 ? list[ 0 ] : list[ Math.min( 1, list.length - 1 ) ];
				} );
		},
		text() {
			return this.plain();
		},
		escaped() {
			return escapeHtml( this.plain() );
		},
		parse() {
			return this.escaped();
		},
		exists() {
			return this.map.exists( this.key );
		},
		toString() {
			return this.text();
		}
	};

	/* --------------------------------------------------------------- Hooks */

	const hooks = Object.create( null );

	/* Like MediaWiki's, a hook remembers what it last fired with, and a
	   handler added afterwards is called with that straight away. */
	function hook( name ) {
		if ( hooks[ name ] ) {
			return hooks[ name ];
		}
		const handlers = [];
		let memory = null;
		hooks[ name ] = {
			add( ...fns ) {
				fns.forEach( ( fn ) => {
					handlers.push( fn );
					if ( memory ) {
						fn( ...memory );
					}
				} );
				return this;
			},
			remove( ...fns ) {
				fns.forEach( ( fn ) => {
					const i = handlers.indexOf( fn );
					if ( i !== -1 ) {
						handlers.splice( i, 1 );
					}
				} );
				return this;
			},
			fire( ...args ) {
				memory = args;
				handlers.slice().forEach( ( fn ) => fn( ...args ) );
				return this;
			},
			deprecate() {
				return this;
			}
		};
		return hooks[ name ];
	}

	/* ------------------------------------------------------------ mw.util */

	const util = {
		throttle( func, wait ) {
			let context, args, timeout, previous = 0;
			const later = () => {
				timeout = null;
				previous = Date.now();
				func.apply( context, args );
			};
			return function () {
				const remaining = wait - ( Date.now() - previous );
				context = this;
				args = arguments;
				if ( remaining <= 0 ) {
					clearTimeout( timeout );
					timeout = null;
					previous = Date.now();
					func.apply( context, args );
				} else if ( !timeout ) {
					timeout = setTimeout( later, remaining );
				}
			};
		},
		debounce( func, wait, immediate ) {
			// MediaWiki accepts the arguments either way round.
			if ( typeof func !== 'function' ) {
				[ func, wait ] = [ wait, func ];
			}
			let timeout;
			return function () {
				const context = this, args = arguments;
				const callNow = immediate && !timeout;
				clearTimeout( timeout );
				timeout = setTimeout( () => {
					timeout = null;
					if ( !immediate ) {
						func.apply( context, args );
					}
				}, wait || 0 );
				if ( callNow ) {
					func.apply( context, args );
				}
			};
		},
		escapeRegExp( str ) {
			return str.replace( /([\\{}()|.?*+\-^$[\]])/g, '\\$1' );
		},
		getParamValue( param, url ) {
			try {
				return new URL( url || location.href ).searchParams.get( param );
			} catch ( e ) {
				return null;
			}
		},
		/* There are no wiki titles to link to, only files. */
		getUrl() {
			return '#';
		},
		getTargetFromFragment( hash ) {
			hash = hash || location.hash.slice( 1 );
			if ( !hash ) {
				return null;
			}
			let target = document.getElementById( hash );
			if ( !target ) {
				try {
					target = document.getElementById( decodeURIComponent( hash ) );
				} catch ( e ) {}
			}
			return target;
		}
	};

	/* --------------------------------------------------------- mw.notify */

	let notificationArea = null;

	function notify( message, options ) {
		options = options || {};
		if ( !notificationArea ) {
			notificationArea = document.createElement( 'div' );
			notificationArea.id = 'mw-notification-area';
			notificationArea.className = 'mw-notification-area mw-notification-area-layout mw-notification-area-floating';
			document.body.appendChild( notificationArea );
		}
		const note = document.createElement( 'div' );
		note.className = 'mw-notification mw-notification-type-' + ( options.type || 'notice' );
		note.setAttribute( 'role', options.type === 'error' ? 'alert' : 'status' );
		if ( options.title ) {
			const title = document.createElement( 'div' );
			title.className = 'mw-notification-title';
			title.textContent = options.title;
			note.appendChild( title );
		}
		const content = document.createElement( 'div' );
		content.className = 'mw-notification-content';
		if ( message instanceof Message ) {
			content.innerHTML = message.parse();
		} else if ( message instanceof Node ) {
			content.appendChild( message );
		} else {
			content.textContent = String( message );
		}
		note.appendChild( content );
		notificationArea.appendChild( note );

		const close = () => {
			note.classList.remove( 'mw-notification-visible' );
			setTimeout( () => note.remove(), 500 );
		};
		note.addEventListener( 'click', close );
		requestAnimationFrame( () => note.classList.add( 'mw-notification-visible' ) );
		if ( options.autoHide !== false ) {
			setTimeout( close, options.autoHideSeconds === 'long' ? 30000 : 5000 );
		}
		return Promise.resolve( { close } );
	}

	/* ---------------------------------------------------------- mw.loader */

	const registry = Object.create( null );

	function resolveRelativePath( relativePath, basePath ) {
		const relParts = relativePath.match( /^((?:\.\.?\/)+)(.*)$/ );
		if ( !relParts ) {
			return null;
		}
		const baseDirParts = basePath.split( '/' );
		baseDirParts.pop();
		const prefixes = relParts[ 1 ].split( '/' );
		prefixes.pop();
		let prefix;
		while ( ( prefix = prefixes.pop() ) !== undefined ) {
			if ( prefix === '..' ) {
				baseDirParts.pop();
			}
		}
		return ( baseDirParts.length ? baseDirParts.join( '/' ) + '/' : '' ) + relParts[ 2 ];
	}

	function injectStyles( name, styles ) {
		const css = styles && styles.css;
		if ( !css || !css.length ) {
			return;
		}
		const style = document.createElement( 'style' );
		style.dataset.module = name;
		style.textContent = css.join( '\n' );
		document.head.appendChild( style );
	}

	/* A packageFiles module: a main file plus files it requires by relative
	   path.  JSON and text files are values; scripts are functions of
	   (require, module, exports), run once, on first require. */
	function runPackage( name, script ) {
		const files = script.files;
		const cache = Object.create( null );

		function requireFile( path ) {
			if ( cache[ path ] ) {
				return cache[ path ].exports;
			}
			if ( !Object.prototype.hasOwnProperty.call( files, path ) ) {
				throw new Error( 'Cannot require undefined file ' + path + ' in ' + name );
			}
			const file = files[ path ];
			const module = { exports: {} };
			cache[ path ] = module;
			if ( typeof file === 'function' ) {
				file( makeRequire( path ), module, module.exports );
			} else {
				module.exports = file;
			}
			return module.exports;
		}

		function makeRequire( basePath ) {
			return ( target ) => {
				const path = resolveRelativePath( target, basePath );
				return path === null ? requireModule( target ) : requireFile( path );
			};
		}

		return requireFile( script.main );
	}

	function execute( name ) {
		const entry = registry[ name ];
		if ( !entry ) {
			throw new Error( 'Unknown module: ' + name );
		}
		if ( entry.state === 'ready' ) {
			return entry.exports;
		}
		if ( entry.state === 'error' ) {
			throw entry.error;
		}
		if ( entry.state === 'executing' ) {
			return entry.module.exports;
		}
		entry.state = 'executing';
		try {
			injectStyles( name, entry.styles );
			const script = entry.script;
			if ( typeof script === 'function' ) {
				script( window.jQuery, window.jQuery, requireModule, entry.module );
			} else if ( script && script.files ) {
				entry.module.exports = runPackage( name, script );
			}
			entry.exports = entry.module.exports;
			entry.state = 'ready';
		} catch ( e ) {
			entry.state = 'error';
			entry.error = e;
			// eslint-disable-next-line no-console
			console.error( 'mw.loader: module ' + name + ' failed', e );
			throw e;
		}
		return entry.exports;
	}

	function requireModule( name ) {
		return execute( name );
	}

	const domReady = document.readyState !== 'loading' ?
		Promise.resolve() :
		new Promise( ( resolve ) => {
			document.addEventListener( 'DOMContentLoaded', resolve, { once: true } );
		} );

	const loader = {
		/* What every vendored module begins with.  The implementation is
		   only recorded here; it runs when it is first used. */
		impl( fn ) {
			const [ key, script, styles, msgs, templates ] = fn();
			const name = key.split( '@' )[ 0 ];
			registry[ name ] = {
				version: key.split( '@' )[ 1 ] || '',
				script,
				styles,
				templates,
				module: { exports: {} },
				state: 'registered'
			};
			if ( msgs ) {
				messages.set( msgs );
			}
		},
		/* Run MODULES once the document is parsed, and resolve with
		   `require', as mw.loader.using does. */
		using( modules ) {
			const names = Array.isArray( modules ) ? modules : [ modules ];
			return domReady.then( () => {
				names.forEach( execute );
				return requireModule;
			} );
		},
		load( modules ) {
			if ( typeof modules === 'string' && /^(https?:)?\/\//.test( modules ) ) {
				// A wiki would fetch a URL; here nothing may leave the page.
				return;
			}
			loader.using( modules ).catch( () => {} );
		},
		getState( name ) {
			return registry[ name ] ? registry[ name ].state : null;
		},
		require: requireModule,
		moduleRegistry: registry
	};

	/* ---------------------------------------------------------------- mw */

	const mw = window.mw = {
		config,
		messages,
		Map: MwMap,
		Message,
		message( key, ...parameters ) {
			return new Message( messages, key, parameters );
		},
		msg( key, ...parameters ) {
			return new Message( messages, key, parameters ).text();
		},
		hook,
		util,
		storage,
		notify,
		loader,
		html: { escape: escapeHtml },
		now: () => performance.now(),
		requestIdleCallback: window.requestIdleCallback ?
			window.requestIdleCallback.bind( window ) :
			( callback ) => setTimeout( () => callback( {
				didTimeout: false,
				timeRemaining: () => 50
			} ), 1 ),
		log: Object.assign( function () {}, {
			// eslint-disable-next-line no-console
			warn: console.warn.bind( console ),
			// eslint-disable-next-line no-console
			error: console.error.bind( console ),
			deprecate() {}
		} ),
		errorLogger: {
			logError( error ) {
				// eslint-disable-next-line no-console
				console.error( error );
			}
		},
		user: {
			isAnon: () => true,
			isNamed: () => false,
			isTemp: () => false,
			getName: () => null,
			options: new MwMap()
		},
		/* Templates are compiled on a wiki by modules this page does not have;
		   nothing here renders one unless a wiki hook asks it to. */
		template: {
			getCompiler( name ) {
				throw new Error( 'mw.template: no ' + name + ' compiler without a wiki' );
			}
		},
		/* There is no API to call. */
		Api: function Api() {
			const reject = () => Promise.reject( new Error( 'mw.Api: no wiki behind this page' ) );
			this.get = reject;
			this.post = reject;
			this.postWithToken = reject;
		}
	};

	/* mediawiki.page.ready: on a wiki it runs once the document is parsed,
	   gives Vue a place to teleport dialogs to, and announces the content to
	   whatever wants to enhance it. */
	loader.impl( () => [ 'mediawiki.page.ready', function ( $, jQuery, require, module ) {
		const teleportTarget = document.createElement( 'div' );
		teleportTarget.id = 'mw-teleport-target';
		teleportTarget.className = 'mw-teleport-target';
		document.body.appendChild( teleportTarget );
		module.exports = { teleportTarget };
	} ] );

	domReady.then( () => {
		execute( 'mediawiki.page.ready' );
		const content = document.getElementById( 'mw-content-text' );
		if ( content ) {
			// Handlers index the argument like the jQuery object a wiki passes.
			hook( 'wikipage.content' ).fire( [ content ] );
		}
	} );
}() );
