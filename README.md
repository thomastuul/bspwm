# bspwm desktop configuration

A personal X11 desktop configuration built around **bspwm**, **sxhkd**, and
two panel implementations:

- **Sliverbar** (`sliverbar/`) is the current native C17 panel and the default
  panel started by `autostart`.
- **Lemonbar** (`lemonbar/`) is the Bash implementation, behavioral reference,
  and fallback panel.

The configuration is intended for a Linux desktop with X11. It is personal
configuration rather than a distribution-neutral installer; review paths,
fonts, optional programs, and power actions before using it on another system.

## Architecture

```text
bspwm
├── bspwmrc
├── sxhkd/sxhkdrc
└── autostart
    ├── sxhkd
    ├── dunst
    ├── sliverbar (default, if ~/.local/bin/sliverbar exists)
    ├── blueman-applet (optional)
    ├── conky (optional)
    ├── nextcloud (optional)
    ├── xss-lock / xsecurelock (optional)
    ├── xautolock (optional)
    └── picom
```

`autostart` uses an advisory lock, validates existing process arguments, writes
diagnostics to the bspwm state directory, and starts optional services only
when their commands or configured executables are available. Sliverbar owns
its own runtime lock. Starting the Bash panel is a manual fallback and must
not be done at the same time as Sliverbar.

## Requirements

### Desktop

- Linux with X11
- bspwm and sxhkd
- Bash 5.1 or newer
- GNU coreutils (`sha256sum`, `setsid`, `stdbuf`, `stat`)
- util-linux (`flock`)
- `awk`, `pgrep`, `xprop`, `xrandr`, `xdpyinfo`, `xset`, and `xsetroot`
- picom and dunst

### Sliverbar

Sliverbar is built and documented independently in the `sliverbar/` submodule.
It uses XCB, Cairo, Pango, GLib/GIO, Fontconfig, and an EWMH-compatible window
manager. See [sliverbar/README.md](sliverbar/README.md) for runtime
dependencies, configuration, packaging, and the supported C17 build workflow.

### Bash fallback

The Bash panel additionally uses lemonbar, trayer, and the tools required by
the enabled modules. Optional integrations include NetworkManager/`nmcli`,
`pamixer`, `pactl` or `amixer`, `curl`, `jq`, an image viewer, Conky,
Nextcloud, xss-lock, XSecureLock, and Nerd Fonts.

## Installation

The repository is intended to live at:

```text
~/.config/bspwm
```

Clone with the Sliverbar submodule when setting up a new checkout:

```bash
git clone --recurse-submodules <repository-url> ~/.config/bspwm
```

Make the entry-point scripts executable and configure bspwm to run:

```bash
~/.config/bspwm/autostart
```

The default autostart panel is expected at:

```text
~/.local/bin/sliverbar
```

For Sliverbar, install or build the binary and copy the example configuration
to `$XDG_CONFIG_HOME/sliverbar/panel.conf` or `$HOME/.config/sliverbar/panel.conf`.
The complete panel setup and module controls are described in
[sliverbar/USAGE.md](sliverbar/USAGE.md).

## Panel selection

### Sliverbar (default)

Build and validate the C17 panel from its submodule:

```bash
cd ~/.config/bspwm/sliverbar
./scripts/quick-check.sh
./scripts/test-local.sh
./scripts/test.sh
```

The validation stages are ordered from fast local checks to the authoritative
container workflow. The resulting local or container binary can be installed
as `~/.local/bin/sliverbar` and started with:

```bash
sliverbar --config ~/.config/sliverbar/panel.conf
```

Validate a configuration without starting a panel:

```bash
sliverbar --config ~/.config/sliverbar/panel.conf --check-config
sliverbar --config ~/.config/sliverbar/panel.conf --diagnose
```

### Lemonbar fallback

Configure the Bash panel in:

```text
lemonbar/config.sh
```

Start it manually only after stopping Sliverbar:

```bash
~/.config/bspwm/lemonbar/start.sh --log
```

Important settings include `TERMINAL`, `PANEL_FONT`, `PANEL_ICON_FONT`,
`TITLE_MAX_LENGTH`, `SIGNAL_DEBOUNCE_DELAY`, `WORKER_RESTART_DELAY`, and
`CACHE_STALE_MAX_AGE`. The Bash implementation uses event-driven realtime
signals, supervised workers, atomic cache publication, and isolated module
failures.

## Runtime state and configuration

The session services use these directories:

```text
$XDG_RUNTIME_DIR/bspwm
$XDG_RUNTIME_DIR/lemonbar
$XDG_RUNTIME_DIR/sliverbar
```

`autostart` writes diagnostics to:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/bspwm/autostart.log
```

Sliverbar stores its state and weather caches according to its configuration;
see [sliverbar/README.md](sliverbar/README.md). The Bash workers use
`$XDG_CACHE_HOME` or `$HOME/.cache` for network and weather caches.

Autostart overrides include:

| Variable | Default |
|---|---|
| `WALLPAPER` | `$HOME/Bilder/Wallpaper/Background.jpg` |
| `CONKY_CONFIG` | `$HOME/.config/conky/conky.conf` |
| `XSECURELOCK_DIMMER` | `/usr/libexec/xsecurelock/dimmer` |
| `AUTOSTART_LOG` | `$XDG_STATE_HOME/bspwm/autostart.log` |

Optional programs are skipped and logged when unavailable. A service that
exits immediately is treated as a failed start and does not receive a
persistent PID file. Re-running `autostart` does not intentionally restart a
healthy service.

## Debugging

Follow autostart diagnostics:

```bash
tail -f "${XDG_STATE_HOME:-$HOME/.local/state}/bspwm/autostart.log"
```

Inspect managed processes:

```bash
pgrep -af 'sliverbar|lemonbar|sighandler|events|title_server|xtmon|network_worker|weather_worker'
```

Inspect runtime state:

```bash
ls -la "$XDG_RUNTIME_DIR/bspwm" "$XDG_RUNTIME_DIR/lemonbar" "$XDG_RUNTIME_DIR/sliverbar"
```

For Bash-panel diagnostics, use `DEBUG=1` and inspect `${TMPDIR:-/tmp}/lemonbar.log`.

## Known limitations

- X11 only; the configuration is not designed for Wayland.
- Paths, fonts, icons, and external programs are machine-specific.
- The default XSecureLock dimmer path is distribution-specific.
- Multi-monitor behavior depends on the active panel and individual module.
- Weather data depends on the configured provider; the Bash fallback uses
  `wttr.in`.
- Network event monitoring works best with NetworkManager.
- Do not display the Bash and C panels simultaneously during visual testing.

## Code style

Code comments, documentation, diagnostics, and command-line help are written
in English. User-facing localized content is added explicitly rather than
mixed into implementation comments.
