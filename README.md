# bspwm desktop configuration

A personal X11 desktop setup built around **bspwm**, **sxhkd**, **lemonbar**, and small Bash services. The panel is event-driven: bspwm, X11, network, weather, volume, brightness, and title changes are converted into realtime signals or atomically published cache files.

## Architecture

```text
autostart
├── sxhkd
├── dunst
├── trayer/start_trayer.sh
├── conky (optional)
├── nextcloud (optional)
├── xss-lock / xsecurelock (optional)
├── xautolock (optional)
├── picom
└── lemonbar/start.sh
    ├── lemonbar
    ├── sighandler.sh
    │   ├── network_worker.sh
    │   └── weather_worker.sh
    ├── events.sh
    └── title_server.sh
        └── xtmon.sh
```

`lemonbar/start.sh` supervises the critical panel processes. If lemonbar, the signal handler, the event listener, or the title server exits, the complete panel is shut down cleanly. The signal handler restarts failed network and weather workers automatically.

Realtime signals are handled by named Bash functions and coalesced before
rendering. Error records include the last handled signal and a function stack to
make rare asynchronous failures diagnosable.

## Design goals

- strict Bash mode (`errexit`, `nounset`, `pipefail`)
- single-instance session services with PID files keyed by complete argument vectors
- early process-start validation and persistent autostart diagnostics
- atomic PID and cache publication
- dedicated runtime directories:
  - `$XDG_RUNTIME_DIR/bspwm`
  - `$XDG_RUNTIME_DIR/lemonbar`
- event coalescing before panel rendering
- isolated module failures: one broken block does not terminate the panel
- stale cache expiration instead of displaying old state indefinitely
- argument-based, validated lemonbar click actions
- no network or weather access in the render loop

## Requirements

### Core

- Linux with X11
- Bash 5.1 or newer
- bspwm
- sxhkd
- lemonbar
- GNU coreutils (`sha256sum`, `setsid`, `stdbuf`, `stat`)
- util-linux (`flock`)
- `awk`, `pgrep`, `xprop`, `xrandr`, `xdpyinfo`, `xset`, `xsetroot`
- trayer
- picom
- dunst
- xwallpaper

### Optional features

- Conky
- Nextcloud desktop client
- NetworkManager / `nmcli`
- `pamixer`, `pactl`, or `amixer`
- `curl`, `jq`, and an image viewer for weather data
- `xss-lock` and XSecureLock
- Nerd Fonts containing the configured glyphs

## Installation

The repository is intended to live at:

```text
~/.config/bspwm
```

Make all entry-point scripts executable and configure bspwm to run:

```bash
~/.config/bspwm/autostart
```

This is a personal configuration, not a distribution-neutral installer. Review all paths and optional components before use.

## Configuration

Main panel settings are in:

```text
lemonbar/config.sh
```

Important variables include:

| Variable | Purpose |
|---|---|
| `TERMINAL` | Terminal used by click actions |
| `PANEL_FONT` | Main lemonbar font |
| `PANEL_ICON_FONT` | Icon font |
| `TITLE_MAX_LENGTH` | Maximum displayed title length |
| `SIGNAL_DEBOUNCE_DELAY` | Signal coalescing window |
| `WORKER_RESTART_DELAY` | Delay before restarting failed workers |
| `CACHE_STALE_MAX_AGE` | Maximum cache age shown by the panel |

Autostart-specific overrides:

| Variable | Default |
|---|---|
| `WALLPAPER` | `$HOME/Bilder/Wallpaper/Background.jpg` |
| `CONKY_CONFIG` | `$HOME/.config/conky/conky.conf` |
| `XSECURELOCK_DIMMER` | `/usr/libexec/xsecurelock/dimmer` |
| `AUTOSTART_LOG` | `$XDG_STATE_HOME/bspwm/autostart.log` |

Brightness, weather, network, and cache behavior can be adjusted through the variables used by their respective modules and workers.

## Runtime state

Session PID and lock files are stored below:

```text
$XDG_RUNTIME_DIR/bspwm
$XDG_RUNTIME_DIR/lemonbar
```

Network and weather output is published through cache files below `$XDG_CACHE_HOME` (or `$HOME/.cache`). Temporary panel state is stored in a private `mktemp` directory and removed during shutdown.

## Realtime signals

Signal numbers are derived dynamically from the platform's `SIGRTMIN`. The configured offsets are:

| Offset | Event |
|---:|---|
| `+2` | workspace |
| `+3` | periodic tick |
| `+5` | active-window title |
| `+6` | volume |
| `+7` | brightness up |
| `+8` | brightness down |
| `+9` | system tray |
| `+10` | network |
| `+11` | screencast |

## Logging and debugging

Autostart diagnostics:

```bash
tail -f "${XDG_STATE_HOME:-$HOME/.local/state}/bspwm/autostart.log"
```

Lemonbar diagnostics:

```bash
tail -f "${TMPDIR:-/tmp}/lemonbar.log"
```

Run the panel with Bash tracing:

```bash
DEBUG=1 ~/.config/bspwm/lemonbar/start.sh --log
```

Inspect the process tree:

```bash
pgrep -af 'lemonbar|sighandler|events|title_server|xtmon|network_worker|weather_worker'
```

Inspect runtime state:

```bash
ls -la "$XDG_RUNTIME_DIR/bspwm" "$XDG_RUNTIME_DIR/lemonbar"
```

## Operational behavior

- Re-running `autostart` does not intentionally restart a healthy lemonbar instance. Lemonbar's own lock rejects duplicates.
- `xwallpaper` sets the root pixmap once and exits; daemon mode is not used.
- Conky is started directly so the recorded PID belongs to the actual process rather than a wrapper script.
- Optional programs are skipped and logged when unavailable.
- A service that exits immediately is treated as a failed start and does not receive a persistent PID file.
- Network and weather caches are removed from the rendered panel after they become stale.

## Known limitations

- X11 only; the configuration is not designed for Wayland.
- Some paths, fonts, icons, and external programs are machine-specific.
- The default XSecureLock dimmer path is distribution-specific.
- Multi-monitor support is present, but individual modules may select the focused or first active output.
- Weather data depends on wttr.in.
- Network event monitoring works best with NetworkManager.

## Code style

Code comments, documentation, diagnostics, and command-line help should be written in English. User-facing localized content should be added explicitly rather than mixed into implementation comments.
