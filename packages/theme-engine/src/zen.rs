//! The look of Zen, the same for every theme: the two stylesheets the theme engine writes after
//! the colours of the theme and the measures of browser.toml (adapters::zen_chrome and
//! adapters::zen_content), which they use by the names `--strix-<name>`. They are kept here as
//! text: Zen takes its look in no other form.

/// For the window of Zen: sidebar, toolbars, tabs, address bar, menus
pub const CHROME: &str = r#"
/* ---------------------------------------------------------------------------------------------
   The shape of Zen in the look of the shell (packages/theme-engine/src/zen.rs, CHROME). The
   colours above change with the theme, the measures above (corners, type, the accent as a line)
   come from browser.toml; what follows uses both and is the same for every theme: the window
   is smoked glass like every plate of the shell, what is pressed is a well in that glass, hair
   lines instead of shadows, the type of the shell, and the accent on what is selected.
   --------------------------------------------------------------------------------------------- */

:root {
  /* What the glass is made of. A well is the ink of the text, thinned: it reads on the dark and
     on the lit part of what shows through, where a fixed colour would not. */
  --strix-glass: color-mix(in srgb, var(--strix-background) var(--strix-glass-cover), transparent);
  --strix-glass-raised: color-mix(in srgb, var(--strix-surface) var(--strix-glass-cover-raised), transparent);
  --strix-line: color-mix(in srgb, var(--strix-text) 14%, transparent);
  --strix-line-strong: color-mix(in srgb, var(--strix-text) 28%, transparent);
  --strix-well: color-mix(in srgb, var(--strix-text) 4%, transparent);
  --strix-well-hover: color-mix(in srgb, var(--strix-text) 7%, transparent);
  --strix-well-selected: color-mix(in srgb, var(--strix-text) 10%, transparent);
  --strix-shadow-panel: 0 14px 36px rgba(0, 0, 0, 0.6);
  /* The motion of the shell: what answers the pointer does so in 140ms, arriving */
  --strix-fast: 140ms cubic-bezier(0.2, 0.8, 0.2, 1);
  --strix-base: 220ms cubic-bezier(0.2, 0.8, 0.2, 1);

  --zen-border-radius: var(--strix-radius) !important;
  --zen-webview-border-radius: var(--strix-radius) !important;
  --zen-native-inner-radius: var(--strix-radius) !important;
  --zen-big-shadow: 0 0 0 1px var(--strix-line) !important;
  --tab-border-radius: var(--strix-radius-control) !important;
  --toolbarbutton-border-radius: var(--strix-radius-control) !important;
  --border-radius-small: var(--strix-radius-control) !important;
  --border-radius-medium: var(--strix-radius-control) !important;
  --arrowpanel-border-radius: var(--strix-radius) !important;
  --panel-border-radius: var(--strix-radius) !important;
  --menuitem-border-radius: var(--strix-radius-item) !important;
  --urlbarView-highlight-background: var(--strix-well-selected) !important;
  --urlbarView-highlight-color: var(--strix-text) !important;
  --focus-outline-color: var(--strix-accent) !important;
  --toolbar-field-focus-border-color: var(--strix-accent) !important;
  --lwt-accent-color: var(--strix-background) !important;
  --lwt-text-color: var(--strix-text) !important;
  --zen-squircle-value: 1 !important;
  /* The toolbars are part of the one sheet of glass, not plates of their own on it */
  --toolbar-bgcolor: transparent !important;
  --zen-urlbar-floating-outline-color: var(--strix-line) !important;
  --zen-urlbar-floating-shadow: var(--strix-shadow-panel) !important;
  --zen-urlbar-outline-offset: -1px !important;
  --arrowpanel-menuitem-border-radius: var(--strix-radius-item) !important;
  --button-border-radius: var(--strix-radius-control) !important;
  --button-background-color-primary: var(--strix-accent) !important;
  --button-background-color-primary-hover: color-mix(in srgb, var(--strix-accent) 88%, white) !important;
  --button-background-color-primary-active: color-mix(in srgb, var(--strix-accent) 88%, black) !important;
  --button-text-color-primary: var(--strix-on-accent) !important;
  /* The names Firefox gives its own parts, which reach into the ones userChrome cannot */
  --color-accent-primary: var(--strix-accent) !important;
  --color-accent-primary-hover: color-mix(in srgb, var(--strix-accent) 88%, white) !important;
  --color-accent-primary-active: color-mix(in srgb, var(--strix-accent) 88%, black) !important;
  --link-color: var(--strix-accent-text) !important;
  --link-color-hover: var(--strix-text) !important;
  --text-color-deemphasized: var(--strix-muted) !important;
  --background-color-box: var(--strix-surface) !important;
  --background-color-information: var(--strix-raised) !important;
  --border-color: var(--strix-border) !important;
  --promo-background-color-vibrant: var(--strix-raised) !important;
  --promo-message-text-color-vibrant: var(--strix-text) !important;
  --promo-border-radius: var(--strix-radius-control) !important;
}
/* The ground of the window: smoked glass. The compositor blurs what lies behind it; with
   glass = 100 in browser.toml it is the solid ground of the theme. Zen sets this colour itself
   on these three, for the space that is shown and the one it comes from. */
:root,
zen-workspace,
.zen-browser-generic-background {
  --zen-main-browser-background: var(--strix-glass) !important;
  --zen-main-browser-background-toolbar: var(--strix-glass) !important;
  --zen-main-browser-background-old: var(--strix-glass) !important;
  --zen-main-browser-background-toolbar-old: var(--strix-glass) !important;
}
/* Zen sets its radii again in the places that use them: the same answer there */
#navigator-toolbox,
.zen-library-space-body,
.tabbrowser-tab,
.toolbarbutton-1,
.urlbar-page-action,
.identity-box-button,
#urlbar,
#zen-media-controls-toolbar {
  --border-radius-medium: var(--strix-radius-control) !important;
  --tab-border-radius: var(--strix-radius-control) !important;
  --toolbarbutton-border-radius: var(--strix-radius-control) !important;
  --urlbar-icon-border-radius: var(--strix-radius-control) !important;
  --urlbar-inner-border-radius: var(--strix-radius-control) !important;
}

/* The type of the shell: its mono for everything that is read, small */
:root,
toolbar,
menupopup,
panel,
.tab-label,
#urlbar,
#urlbar-input,
.urlbarView {
  font-family: var(--strix-font) !important;
  font-size: var(--strix-font-size) !important;
  letter-spacing: 0 !important;
}

/* ---- Tabs: flat rows; the selected one is a well and carries the accent at its edge ---- */
zen-workspace,
.tabbrowser-tab,
#tabs-newtab-button {
  --tab-background-color-selected: var(--strix-well-selected) !important;
  --tab-selected-bgcolor: var(--strix-well-selected) !important;
  --tab-background-color-hover: var(--strix-well-hover) !important;
  --tab-box-shadow-selected: var(--strix-stroke) !important;
  --tab-text-color-selected: var(--strix-text) !important;
}
.tabbrowser-tab .tab-background {
  border-radius: var(--strix-radius-control) !important;
  box-shadow: none !important;
  outline: none !important;
  transition: background-color var(--strix-fast), box-shadow var(--strix-fast) !important;
}
.tabbrowser-tab:is([visuallyselected], [multiselected]) .tab-background {
  background: var(--strix-well-selected) !important;
  box-shadow: var(--strix-stroke) !important;
}
.tabbrowser-tab:not([visuallyselected], [multiselected]):hover .tab-background {
  background: var(--strix-well-hover) !important;
}
.tabbrowser-tab .tab-label {
  color: var(--strix-muted) !important;
  transition: color var(--strix-fast) !important;
}
.tabbrowser-tab:is([visuallyselected], [multiselected], :hover) .tab-label {
  color: var(--strix-text) !important;
}
.tabbrowser-tab .tab-close-button {
  border-radius: var(--strix-radius-control) !important;
  color: var(--strix-muted) !important;
}
.tabbrowser-tab .tab-close-button:hover {
  background: var(--strix-well-selected) !important;
  color: var(--strix-text) !important;
}
/* Essentials: wells in the glass; the selected one is deeper, with the accent under it */
.tabbrowser-tab[zen-essential] {
  --zen-essential-tab-selected-bg: var(--strix-well-selected) !important;
  --zen-essential-tab-selected-bg-hover: var(--strix-well-selected) !important;
}
.tabbrowser-tab[zen-essential] .tab-background {
  border-radius: var(--strix-radius-control) !important;
}
.tabbrowser-tab[zen-essential]:not([visuallyselected], [multiselected]) .tab-background {
  background: var(--strix-well) !important;
}
.tabbrowser-tab[zen-essential]:not([visuallyselected], [multiselected]):hover .tab-background {
  background: var(--strix-well-hover) !important;
}
.tabbrowser-tab[zen-essential]:is([visuallyselected], [multiselected]) .tab-background {
  box-shadow: var(--strix-stroke-under) !important;
}
.tabbrowser-tab[zen-essential] .tab-background::before,
.tabbrowser-tab[zen-essential] .tab-background::after {
  border-radius: var(--strix-radius-item) !important;
}
/* Folders, and the list a folder shows of its tabs */
zen-folder > .tab-group-label-container,
.folders-tabs-list-item-content {
  border-radius: var(--strix-radius-control) !important;
}
/* A tab that plays or is muted keeps its mark in the accent */
.tab-icon-overlay,
.tab-audio-button {
  color: var(--strix-accent-text) !important;
}

/* The new tab row and the names of spaces and folders: quiet until the pointer is there */
#tabs-newtab-button,
#vertical-tabs-newtab-button,
.zen-workspace-tabs-section .toolbarbutton-1,
.zen-current-workspace-indicator {
  color: var(--strix-muted) !important;
  border-radius: var(--strix-radius-control) !important;
  transition: background-color var(--strix-fast), color var(--strix-fast) !important;
}
/* While the address bar stands in for a new tab, its row is the selected one */
#tabs-newtab-button[in-urlbar] {
  background: var(--strix-well-selected) !important;
  box-shadow: var(--strix-stroke) !important;
  color: var(--strix-text) !important;
}
.zen-current-workspace-indicator .zen-current-workspace-indicator-name {
  font-family: var(--strix-font) !important;
  /* A label of the shell: semibold, sentence case, as the person wrote it */
  font-size: calc(var(--strix-font-size) - 1px) !important;
  font-weight: 600 !important;
  text-transform: none !important;
  letter-spacing: 0 !important;
  color: var(--strix-muted) !important;
}

/* ---- The address bar. In the strip it is a field of the shell: a well without a frame. Over
   the page it is the search of the shell: a plate of smoked glass with a hair line and the
   shadow of a panel, so what the search hands to Zen arrives in the same place. The accent is
   the caret and the line on the chosen row, not a frame. ---- */
#urlbar .urlbar-background,
#urlbar-background,
#searchbar {
  border-radius: var(--strix-radius-control) !important;
  border: none !important;
  background: var(--strix-well) !important;
  box-shadow: none !important;
  outline: 1px solid transparent !important;
  outline-offset: -1px !important;
  transition: background-color var(--strix-fast), outline-color var(--strix-fast) !important;
}
#urlbar:not([breakout-extend]):hover .urlbar-background,
#urlbar:not([breakout-extend]):hover #urlbar-background {
  background: var(--strix-well-hover) !important;
}
#urlbar[focused]:not([breakout-extend]) .urlbar-background,
#urlbar[focused]:not([breakout-extend]) #urlbar-background {
  outline-color: var(--strix-line-strong) !important;
}
#urlbar[breakout-extend],
#urlbar[breakout-extend] .urlbar-background,
#urlbar[breakout-extend] #urlbar-background {
  border-radius: var(--strix-radius) !important;
}
#urlbar[breakout-extend] .urlbar-background,
#urlbar[breakout-extend] #urlbar-background {
  background: var(--strix-glass-raised) !important;
  backdrop-filter: blur(24px) !important;
  outline: 1px solid var(--strix-line) !important;
  outline-offset: -1px !important;
  box-shadow: var(--strix-shadow-panel) !important;
}
#urlbar-input {
  caret-color: var(--strix-accent) !important;
}
#urlbar-input::placeholder {
  color: var(--strix-faint) !important;
  opacity: 1 !important;
}
/* Where the address bar was while it floats over the page, and the marks inside it */
#urlbar-container,
#notification-popup-box,
#urlbar .urlbar-page-action,
#urlbar #tracking-protection-icon-container,
#urlbar #identity-box,
#urlbar #identity-icon-box,
#urlbar .searchbar-engine-one-off-item,
#urlbar .urlbarView-favicon {
  border-radius: var(--strix-radius-control) !important;
}
#urlbar-input::selection {
  background: var(--strix-accent) !important;
  color: var(--strix-on-accent) !important;
}
.urlbarView-row {
  border-radius: var(--strix-radius-item) !important;
}
.urlbarView-row[selected] {
  background: var(--strix-well-selected) !important;
  box-shadow: var(--strix-stroke) !important;
}
.urlbarView-row:hover:not([selected]) {
  background: var(--strix-well-hover) !important;
}
.urlbarView-row[selected] .urlbarView-row-inner,
.urlbarView-row:hover .urlbarView-row-inner {
  background: none !important;
}
.urlbarView-url,
.urlbarView-action {
  color: var(--strix-accent-text) !important;
}

/* ---- Buttons of the toolbars: symbols in the muted ink, a well under the pointer ---- */
toolbarbutton,
.toolbarbutton-1 {
  --toolbarbutton-hover-background: var(--strix-well-hover) !important;
  --toolbarbutton-active-background: var(--strix-well-selected) !important;
  color: var(--strix-muted) !important;
  fill: currentColor !important;
  transition: color var(--strix-fast) !important;
}
toolbarbutton:is(:hover, [open], [checked]),
.toolbarbutton-1:is(:hover, [open], [checked]) {
  color: var(--strix-text) !important;
}
toolbarbutton > .toolbarbutton-icon,
toolbarbutton > .toolbarbutton-badge-stack {
  border-radius: var(--strix-radius-control) !important;
  transition: background-color var(--strix-fast) !important;
}

/* ---- The page: the radius of a window and a hair line (the big shadow above) around it;
   the ground of the theme behind a page that has not painted yet ---- */
#tabbrowser-tabpanels browser[type="content"]:not([transparent="true"]) {
  background: var(--strix-background) !important;
}
/* A tab without a page is a well in the glass of the window, as where the page will be in the
   search of the shell, instead of Zen's grey sheet */
#tabbrowser-tabbox #tabbrowser-tabpanels .browserSidebarContainer {
  --zen-transparent-browser-background: var(--strix-well) !important;
}

/* ---- Menus, panels and hints: plates of smoked glass, as what drops out of the bar ---- */
menupopup,
panel {
  --panel-background: var(--strix-glass-raised) !important;
  --panel-color: var(--strix-text) !important;
  --panel-border-color: var(--strix-line) !important;
  --panel-border-radius: var(--strix-radius) !important;
  --panel-shadow: 0 8px 22px rgba(0, 0, 0, 0.5) !important;
  --panel-padding: 4px !important;
  --panel-separator-color: var(--strix-line) !important;
  --arrowpanel-background: var(--strix-glass-raised) !important;
  --arrowpanel-border-color: var(--strix-line) !important;
}
menu,
menuitem,
.subviewbutton,
.panel-subview-body toolbarbutton {
  border-radius: var(--strix-radius-item) !important;
  color: var(--strix-text) !important;
}
:is(menu, menuitem)[_moz-menuactive],
.subviewbutton:hover {
  background: var(--strix-well-selected) !important;
  color: var(--strix-text) !important;
  box-shadow: var(--strix-stroke) !important;
}
:is(menu, menuitem)[disabled] {
  color: var(--strix-faint) !important;
}
menuseparator,
toolbarseparator {
  border-color: var(--strix-line) !important;
  appearance: none !important;
}
tooltip {
  appearance: none !important;
  background: var(--strix-raised) !important;
  color: var(--strix-text) !important;
  border: 1px solid var(--strix-border) !important;
  border-radius: var(--strix-radius-item) !important;
  padding: 2px 6px !important;
}

/* ---- Dialogs and what Zen says in a corner ---- */
.dialogBox {
  border-radius: var(--strix-radius) !important;
  border: 1px solid var(--strix-border) !important;
  outline: none !important;
  background: var(--strix-surface) !important;
  box-shadow: 0 8px 22px rgba(0, 0, 0, 0.5) !important;
}
dialog::part(dialog-button),
.zen-big-accent-button,
.footer-button,
button.subviewbutton-nav,
.panel-footer > button {
  border-radius: var(--strix-radius-control) !important;
}
#zen-toast-container .zen-toast {
  border-radius: var(--strix-radius-control) !important;
  border: 1px solid var(--strix-border) !important;
  background: var(--strix-raised) !important;
  color: var(--strix-text) !important;
  box-shadow: none !important;
}
/* What plays, and what the sidebar reports: a card with a hair line */
:root {
  --zen-sidebar-notification-shadow: none !important;
  --zen-sidebar-notification-outline: 1px solid var(--strix-border) !important;
}
.zen-media-card {
  border-radius: var(--strix-radius-control) !important;
}

/* ---- Small things ---- */
/* Find in page and the bars a page can show under the toolbar */
findbar,
notification-message,
.infobar {
  background: var(--strix-surface) !important;
  color: var(--strix-text) !important;
  border-color: var(--strix-border) !important;
  border-radius: 0 !important;
}
/* What takes the keyboard shows the accent, never a blue ring */
:focus-visible {
  outline-color: var(--strix-accent) !important;
}
/* Thin scrollbars in the ink of the borders */
* {
  scrollbar-width: thin;
  scrollbar-color: var(--strix-border-strong) transparent;
}
"#;

/// For the pages of the browser itself (new tab, settings, about:), inside the rule that names
/// those pages
pub const CONTENT: &str = r#"
  /* -------------------------------------------------------------------------------------------
     The pages of the browser itself in the look of the shell
     (packages/theme-engine/src/zen.rs, CONTENT). They draw themselves from the names Firefox
     gives its colours and shapes, so those names are answered here; the same for every theme.
     ------------------------------------------------------------------------------------------- */
  :root {
    --zen-primary-color: var(--strix-accent) !important;
    --zen-colors-primary: var(--strix-accent) !important;
    --zen-colors-secondary: var(--strix-raised) !important;
    --zen-colors-tertiary: var(--strix-surface) !important;
    --zen-colors-border: var(--strix-border) !important;
    --zen-dialog-background: var(--strix-surface) !important;
    --zen-squircle-value: 1 !important;

    --background-color-canvas: var(--strix-background) !important;
    --background-color-box: var(--strix-surface) !important;
    --background-color-box-info: var(--strix-surface) !important;
    --background-color-information: var(--strix-raised) !important;
    --table-background-color: var(--strix-surface) !important;
    --table-row-background-color: var(--strix-background) !important;
    --table-row-background-color-alternate: var(--strix-surface) !important;
    --text-color: var(--strix-text) !important;
    --text-color-deemphasized: var(--strix-muted) !important;
    --icon-color: var(--strix-muted) !important;
    --border-color: var(--strix-border) !important;
    --border-color-card: var(--strix-border) !important;
    --border-color-deemphasized: var(--strix-border) !important;
    --border-color-interactive: var(--strix-border-strong) !important;
    --table-border-color: var(--strix-border) !important;

    --color-accent-primary-hover: color-mix(in srgb, var(--strix-accent) 88%, white) !important;
    --color-accent-primary-active: color-mix(in srgb, var(--strix-accent) 88%, black) !important;
    --color-accent-primary-selected: var(--strix-accent) !important;
    --focus-outline-color: var(--strix-accent) !important;
    --link-color: var(--strix-accent-text) !important;
    --link-color-hover: var(--strix-text) !important;
    --link-color-active: var(--strix-text) !important;
    --link-color-visited: var(--strix-accent-text) !important;

    --button-background-color: var(--strix-raised) !important;
    --button-background-color-hover: var(--strix-border) !important;
    --button-background-color-active: var(--strix-border-strong) !important;
    --button-text-color: var(--strix-text) !important;
    --button-background-color-primary: var(--strix-accent) !important;
    --button-background-color-primary-hover: var(--color-accent-primary-hover) !important;
    --button-background-color-primary-active: var(--color-accent-primary-active) !important;
    --button-text-color-primary: var(--strix-on-accent) !important;
    --input-background-color: var(--strix-sunken) !important;

    /* The corners of browser.toml, hair lines instead of shadows */
    --border-radius-xsmall: var(--strix-radius-item) !important;
    --border-radius-small: var(--strix-radius-control) !important;
    --border-radius-medium: var(--strix-radius-control) !important;
    --border-radius-large: var(--strix-radius) !important;
    --button-border-radius: var(--strix-radius-control) !important;
    --box-shadow-level-1: none !important;
    --box-shadow-level-2: none !important;
    --box-shadow-level-3: 0 8px 22px rgba(0, 0, 0, 0.5) !important;
    --box-shadow-level-4: 0 8px 22px rgba(0, 0, 0, 0.5) !important;
    --card-box-shadow: none !important;

    /* The type of the shell */
    font-family: var(--strix-font) !important;
    scrollbar-width: thin;
    scrollbar-color: var(--strix-border-strong) transparent;
  }
  ::selection {
    background: var(--strix-accent);
    color: var(--strix-on-accent);
  }

  /* Settings: what Zen shapes by hand */
  groupbox button,
  groupbox menulist {
    border-radius: var(--strix-radius-control) !important;
    background-color: var(--strix-raised) !important;
    color: var(--strix-text) !important;
  }
  /* The list of pages at the side: the selected one is raised and carries the accent */
  moz-page-nav-button {
    --page-nav-button-border-radius: var(--strix-radius-control) !important;
    --page-nav-button-text-color: var(--strix-muted) !important;
    --page-nav-button-text-color-hover: var(--strix-text) !important;
    --page-nav-button-text-color-selected: var(--strix-text) !important;
    --page-nav-button-background-color-hover: color-mix(in srgb, var(--strix-raised) 55%, transparent) !important;
    --page-nav-button-background-color-selected: var(--strix-raised) !important;
    --page-nav-button-indicator-background-color: var(--strix-accent) !important;
  }
"#;
