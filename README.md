# Dock, with extras

> **This is a fork.** It is elementary's [Dock](https://github.com/elementary/dock) with
> three additions:
>
> - **Folder stacks**, as on macOS: a folder after the launchers that opens as a fan
>   (Downloads, newest first) or a grid (Applications, with its folders). Partial
>   downloads show their progress. Drag a folder from Files onto the dock to add one;
>   right-click a stack to change how it looks or remove it.
> - **Zoom:** the icons near the pointer grow and their neighbours spread apart.
> - **Sharp icons:** zoomed and tilted icons are looked up at the size they cover on
>   screen, so they never show a stretched bitmap.
>
> - **Branch:** `extras` (the default here) is upstream's `8.3.3` release plus one commit
>   per feature, then this README and the Debian packaging. `main` tracks upstream
>   unchanged. See `git log 8.3.3..extras`.
> - **Status:** experimental, used daily on NixOS. Not affiliated with elementary, and
>   not proposed upstream.
>
> - **Install on elementary OS 8** from the signed apt repo at
>   [arsfeld.github.io/pantheon-apt](https://arsfeld.github.io/pantheon-apt), which replaces elementary's
>   `io.elementary.dock` with `io.elementary.dock-extras`:
>
>   ```sh
>   sudo curl -fsSLo /usr/share/keyrings/pantheon-apt.gpg https://arsfeld.github.io/pantheon-apt/pantheon-apt.gpg
>   echo "deb [signed-by=/usr/share/keyrings/pantheon-apt.gpg] https://arsfeld.github.io/pantheon-apt noble main" \
>     | sudo tee /etc/apt/sources.list.d/pantheon-apt.list
>   sudo apt update && sudo apt install io.elementary.dock-extras
>   ```
>
>   Log out and back in to start it. `sudo apt install io.elementary.dock` goes back to
>   elementary's.
>
> - **Settings** are in gsettings. Zoom is on by default; stacks are empty until you add
>   one, or set them:
>
>   ```sh
>   gsettings set io.elementary.dock stacks "[('~/Downloads', 'fan', 'date-added', 'stack'), ('applications', 'grid', 'name', 'grid')]"
>   gsettings set io.elementary.dock zoom-size 84   # or: zoom-enabled false
>   ```
>
>   Each stack is `(source, view, sort, display)`: source is an absolute path, a path
>   starting with `~/`, or `applications`; view `fan` or `grid`; sort `date-added` or
>   `name`; display `stack`, `grid` or `folder`. Install progress on the Applications
>   stack needs an AppCenter that publishes its jobs, which elementary's does not, so
>   on elementary OS it shows none.
>
> Everything below is upstream's README.

# Dock

A quick app launcher and window switcher for Pantheon

## Building, Testing, and Installation

You'll need the following dependencies:

* libadwaita-1-dev
* libgranite-7-dev >= 7.7.0
* libgtk-4-dev
* meson
* valac

Run `meson` to configure the build environment and then `ninja test` to build and run tests

    meson build --prefix=/usr
    cd build
    ninja test

To install, use `ninja install`, then execute with `io.elementary.dock`

    ninja install
    io.elementary.dock
