# Working on the extras branch

`extras` is elementary's `8.3.3` plus one commit per feature (stacks in `src/Stacks`, zoom in
`src/Zoom`, sharp icons in `src/Icons`), a README commit and a packaging commit on top. Keep
that shape: a fix to a feature is a fixup of that feature's commit
(`git commit --fixup <sha>`, then `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash 8.3.3`),
and a new feature is a new commit before the README. Rebasing onto a new upstream release
moves the base tag in those commands.

Designs live in arsfeld/nixos under `docs/superpowers/specs/` (`2026-10-31-dock-stacks-design.md`,
`2026-10-31-dock-zoom-design.md`, `2026-11-03-dock-sharp-icons-design.md`,
`2026-11-13-elementary-dock-extras-design.md`).

## Building

- **elementary OS 8 (the .deb):** `ci/build-deb.sh` in `ghcr.io/elementary/docker:stable`, the
  same as CI. It runs the three unit tests (`stacks`, `zoom-math`, `icon-math`).
- **NixOS:** arsfeld/nixos pins this branch as `packages/elementary-dock-extras`. Its
  `just pantheon::dock-run <log> <this checkout> VAR=value…` builds a checkout, swaps it into
  raider's live session and `just pantheon::shot` screenshots it; the visual loop and its
  pitfalls are documented in `modules/desktop/pantheon-dock/CLAUDE.md` there.
- **Two GTKs.** elementary OS 8 ships an older GTK than nixpkgs' 4.22. Code that uses newer
  API goes behind a meson-detected Vala define, as `HAS_GTK_4_22` does for
  `Gtk.SymbolicPaintable.snapshot_with_weight` (`meson.build`, `src/Icons/IconResolution.vala`).
  A build that is green on NixOS and red in CI is usually this.
- **Core sources stay display-free.** Each feature's unit test links only its core files
  (see the feature's `meson.build`) and runs with no display, in the Nix sandbox and in
  `dh_auto_test` alike.

## Test hooks

A build that compiles and passing unit tests say nothing about how the dock looks; the stacks
fan passed review twice and was badly wrong on screen. Look at it, and open what you need to
see through a test hook, never by injecting input:

- **Never inject input.** ydotool's `--absolute` is a series of relative moves bent by pointer
  acceleration, so it misses. It also moves the pointer of the person working at the machine.
  Open what you need to see through a test hook instead. For the stacks that hook is
  `DOCK_STACKS_OPEN=<index into stacks>`, which pops that stack's popover about 1.5 s after each matching StackItem is built, and again
  whenever `stacks` changes (`src/Stacks/StackItem.vala`).
  `DOCK_STACKS_CLICK=<row>[@<progress>]`, set alongside it, plays that fan row's launch
  animation and the tile bounce 0.7 s after the fan opens, without opening anything; with
  a progress (0–1) the fan holds at that frame, which is the only way to screenshot it.
  `DOCK_STACKS_FOLDER=<folder name>`, with `DOCK_STACKS_OPEN` on the Applications grid, opens
  that folder (`Games`, `System`, `Utilities`, `Terminal Tools`).
  `DOCK_STACKS_FAKE_JOB=<desktop-id>:<state>:<progress>` injects one AppCenter job at start
  (state 1 installing, 2 updating, 3 removing); with state 1, an id with no desktop file is a new
  install.
  Fake jobs survive AppCenter leaving the bus, because `clear ()` keeps `fake.` ids.
  Download progress needs no hook: append to `~/Downloads/<name>.part` slowly, and for a real
  fraction also have a `.crdownload` and `gdbus emit` a `com.canonical.Unity.LauncherEntry.Update`. That works only if the
  `application://` id is an installed desktop file whose `MimeType` lists
  `x-scheme-handler/https`.
  `DOCK_STACKS_MENU=<index into stacks>` opens that stack's right-click menu instead,
  1.5 s after it is built. `DOCK_STACKS_DROP=<path>` runs the folder-drop path for that
  path 1 s after start (`src/ItemManager.vala`); it writes `stacks` to user dconf like a
  real drop, so `dconf reset /io/elementary/dock/stacks` afterwards.
  For the zoom it is `DOCK_ZOOM_AT=<slots>`, which zooms the
  dock 1 s after start as if the pointer rested that many launcher widths from its left edge
  (`src/ItemManager.vala`, from the zoom commit). It fires before `DOCK_STACKS_OPEN`, so the two
  combine. Give new UI the same kind of hook.

## Vala pitfalls that bit here

- **Lambdas inside an `Object (...)` chain-up** are compiled as closures over a NULL `this`,
  and the result is a `g_object_unref` critical on finalize. Use a static method.
- **Dock items are never freed on their own.** `BaseIconGroup`'s `bind_model` delegate, and
  the animation callbacks behind `BaseItem.cleanup ()`, both hold the item. Upstream never
  calls `cleanup ()`. `StackItem` tears itself down when its parent goes null; anything new
  that the dock removes at runtime needs the same treatment.
- **Signal handlers on long-lived objects** (a `StackSource`, its `entries`) should be
  methods, not lambdas that capture locals. Each removal path should be verified with
  `G_MESSAGES_DEBUG=all` and the teardown/finalize debug lines.
- **valac's `warning ()` prefixes `File.vala:LINE: `.** A `Test.expect_message` pattern
  needs a leading `*`, and GLib tests make any unexpected warning fatal.

## Icon resolution

`Gtk.Image` rasterizes its icon for the widget's scale factor only. Anything that scales it
afterwards — the zoom's item transform, `StackRender`'s supersampled texture — stretches a
1× bitmap, which is what made zoomed and tilted icons blurry. So a dock image whose icon may
be drawn larger than its `pixel_size` gets its icon through `IconResolution.attach (image,
icon, oversample)` (`src/Icons/`), never through `gicon`: set `icon` on the helper, bind
`render-scale` from its `BaseItem`, and pass `StackRender.OVERSAMPLE` if it is painted
tilted. `BaseItem.render_scale` is `ceil (zoom)` and 1 at rest, so resting icons keep their
native bitmaps. Popover images that are neither zoomed nor tilted (the Applications grid)
need none of this.

The helper sets a private `SharpPaintable` wrapper on the image, not the `Gtk.IconPaintable`
it looked up. `gtk_icon_helper_load_paintable ()` in GTK 4.22's `gtk/gtkiconhelper.c`
(around lines 129-132) resets the `scale` of any bare `Gtk.IconPaintable` to the widget's
scale factor, which silently throws the high-resolution lookup away. A wrapper is not an
icon paintable, so GTK leaves it alone, and it still implements `Gtk.SymbolicPaintable`, so
icon CSS (`-gtk-icon-shadow`, symbolic recolouring) keeps applying. Do not simplify it back
to `image.paintable = <lookup result>`.

## GTK 4.22 and elementary's icons

GTK 4.22 draws 399 of elementary-icon-theme's SVGs fully transparent, including
`text-x-generic` and `application-pdf`. Those files spell the xlink namespace `nsN:`, and
GTK's own SVG renderer matches only a literal `xlink:href`. librsvg renders them fine, so
`rsvg-convert` is no test. arsfeld/nixos ships corrected copies
(`elementaryIconFix` in `modules/desktop/desktop.nix`); elementary OS does not need them,
since its GTK is older. A "blank" icon anywhere in Pantheon is this before it is anything else.
