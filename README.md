# bspwm desktop configuration

A personal X11 desktop configuration built around **bspwm**, **sxhkd**, and
the Sliverbar panel:

- **Sliverbar** (`sliverbar/`) is the current native C17 panel and the default
  panel started by `autostart`.
Lemonbar was deliberately removed in commit `0cd26fe` (#126). It is a
historical implementation, not an installed fallback. Its source remains in
Git history; do not use its old launch commands with this checkout.

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

## Host profiles

The bspwm configuration is shared by all machines. Generic defaults live in
`lib/host-profile.sh`; machine-specific overrides live in:

```text
hosts/
├── Ikarus2/
│   └── profile.sh
└── Pegasus4/
    └── profile.sh
```

Only `Ikarus2` and `Pegasus4` are supported, case-insensitively. Set
`BSPWM_HOST_OVERRIDE=Ikarus2` or `BSPWM_HOST_OVERRIDE=Pegasus4` to select one.
Other names (including historical `Ikarus`) produce a diagnostic on stderr
and use common emergency defaults so that the desktop can still start.
They never load additional profile directories or panel files. Correct the
hostname or override to restore the intended configuration; no fuzzy aliases
are supported.

Profiles may override `BSPWM_TOP_PADDING`, `BSPWM_WALLPAPER`,
`BSPWM_ENABLE_SLIVERBAR`, `BSPWM_ENABLE_CONKY`, `BSPWM_ENABLE_BLUEMAN`,
`BSPWM_ENABLE_NEXTCLOUD`, `BSPWM_ENABLE_SCREEN_LOCK`,
`BSPWM_ENABLE_AUTOLOCK`, and `BSPWM_ENABLE_PICOM`. Boolean switches accept
`1/0`, `true/false`, `yes/no`, `on/off`, and `enabled/disabled`.

Sliverbar remains machine-independent. If a host needs an exceptional panel
configuration, place it at `hosts/Ikarus2/sliverbar.conf` or
`hosts/Pegasus4/sliverbar.conf` or set
`SLIVERBAR_CONFIG` in that host's `profile.sh`. Otherwise Sliverbar uses its
normal configuration search. Priority is a nonempty assignment in the host
profile, then a readable host-local file, then Sliverbar's normal search.
Empty profile values permit fallback. An incoming `SLIVERBAR_CONFIG` environment
value is deliberately reset on loading, including in a child process that
selects a different host. No environment override has been added.

### Laptop display profiles

On Ikarus2, the explicitly configured `BSPWM_INTERNAL_OUTPUT=eDP-1` and
`BSPWM_EXTERNAL_OUTPUT=HDMI-1` enable the `mobile`/dock desktop reconciliation.
Pegasus4 has no output pair and skips that consolidation. Both retain the
previous `remove_disabled_monitors=true` and `remove_unplugged_monitors=false`
settings. These do not promise retention of every disabled output. The hook merges duplicate
workspace names, transfers every window to the remaining active monitor,
removes the inactive bspwm monitor, and synchronizes its rectangle with
RandR. The `xwallpaper` daemon started by `autostart` listens for these RandR
changes and redraws the complete wallpaper without cropping. The hook also
restarts Sliverbar through the idempotent session launcher if the panel exited
during the topology change.

Ikarus2 uses Debian's `autorandr` integration and these profiles below
`~/.config/autorandr/`:

- `mobile`: internal `eDP-1` only
- `dock-open`: internal `eDP-1` and external `HDMI-1`
- `dock-closed`: external `HDMI-1` as primary; internal output disabled

The packaged `autorandr-lid-listener.service` selects between the open and
closed dock profiles when the lid state changes. The global autorandr
`postswitch` symlink points to `bin/autorandr-postswitch.sh`. To undo the
display-specific configuration, remove those three profile directories and
the symlink after backing them up. The unchanged bspwm removal settings are
independent and should not be removed as part of that rollback. The hook runs
after autorandr changes modes; it does not detect hardware itself. On the
inspected Ikarus2 installation there is also an external user service
`autorandr-resume-watch.service`, ordered after `graphical-session.target`,
which can invoke autorandr. No additional watcher is installed here.
Pegasus4's external profiles, hooks and service ordering still require inspection.
See [implementation and validation notes](docs/host-improvements.md).

### Optional session programs

Optional integrations include Conky, Nextcloud, Blueman, xss-lock,
XSecureLock, xautolock and xwallpaper.

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
see [sliverbar/README.md](sliverbar/README.md). The legacy Lemonbar runtime
directory is still created for compatibility with `bin/screencast.sh`, whose
old Lemonbar integration is obsolete; use `bin/start_recording.sh` and
`bin/stop_recording.sh` through the configured shortcuts instead.

Autostart overrides include:

| Variable | Default |
|---|---|
| `WALLPAPER` | Selected host's `BSPWM_WALLPAPER` |
| `CONKY_START` | `$XDG_CONFIG_HOME/conky/start-conky.sh` (default config home: `$HOME/.config`) |
| `XSECURELOCK_DIMMER` | `/usr/libexec/xsecurelock/dimmer` |
| `AUTOSTART_LOG` | `$XDG_STATE_HOME/bspwm/autostart.log` |

Optional programs are skipped and logged when unavailable. A service that
exits immediately is treated as a failed start and does not receive a
persistent PID file. Re-running `autostart` does not intentionally restart a
healthy service. Feature switches control starts, not stops: disabling a
feature requires a new login session or a targeted stop through its actual
process/service owner. Re-running autostart does not generally reconfigure
running programs. Conky is an explicit exception: its generated geometry is
refreshed through the same serialized path as the autorandr hook.

### Screen locking and idle power

Both hosts keep their existing behavior; the desktop role does not disable sleep.

| Mechanism | Control | Timing / action |
|---|---|---|
| Screen lock | `BSPWM_ENABLE_SCREEN_LOCK` | `xss-lock -n /usr/libexec/xsecurelock/dimmer --transfer-sleep-lock -- xsecurelock`; saver at 300 seconds, cycle 10 seconds, dimmer defaults to 10000 ms |
| Display power | Unconditional `xset +dpms` | `xset dpms 400 600 900`: standby, suspend, off in seconds |
| Automatic system sleep | `BSPWM_ENABLE_AUTOLOCK` (legacy name retained) | `xautolock -time 30 -detectsleep -locker 'systemctl suspend-then-hibernate'` |

Disabling the locking or AUTOLOCK switch does not disable DPMS. The sleep command
requests a system action; its success depends on logind, sleep configuration and
hibernation support. No energy policy or system service has been changed here.

### Conky after a display change

`bin/conky-refresh.sh` is shared by autostart and autorandr, independently of
Sliverbar, and respects `BSPWM_ENABLE_CONKY`. The external `CONKY_START` generator
must implement `CONKY_GENERATE_ONLY=1` and write `conky-$UID.conf` under the supplied
`XDG_RUNTIME_DIR`, without starting/stopping processes in that mode. The inspected
Ikarus2 launcher supports this contract. Its template and Lua helper remain
external prerequisites; Pegasus4's launcher must be checked before deployment.

A lock serializes generation and reload. Generation happens in a temporary
directory, followed by atomic publication. Only current-user Conky processes
with the exact managed `--config=.../conky-$UID.conf` argument receive `SIGUSR1`.
Other Conky instances are untouched. If none exists, the helper starts one.
Unchanged configuration and a running instance require no reload. Do not run the
external launcher directly in parallel: its legacy `pkill -x conky` is still
outside this integration's ownership.

The primary active output is the target, otherwise the first active output.
The matching Xinerama rectangle selects the head, including monitor offsets;
`bottom_left` and the generator's margins remain in effect. The inspected
generator supports nonnegative RandR offsets. Unsupported geometry or a missing
Xinerama head fails explicitly; the previous configuration remains intact.
No permanent monitor watcher is added. A changed topology during generation
aborts publication and is retried by the next hook invocation.

## Debugging

Follow autostart diagnostics:

```bash
tail -f "${XDG_STATE_HOME:-$HOME/.local/state}/bspwm/autostart.log"
```

Inspect managed processes:

```bash
pgrep -af 'sliverbar|conky|sxhkd|picom'
```

Inspect runtime state:

```bash
ls -la "$XDG_RUNTIME_DIR/bspwm" "$XDG_RUNTIME_DIR/lemonbar" "$XDG_RUNTIME_DIR/sliverbar"
```


## Known limitations

- X11 only; the configuration is not designed for Wayland.
- Paths, fonts, icons, and external programs are machine-specific.
- The default XSecureLock dimmer path is distribution-specific.
- Multi-monitor behavior depends on the active panel and individual module.
- Weather data depends on the configured provider.
- Network event monitoring works best with NetworkManager.
- Historical Lemonbar code must be tested separately from Sliverbar.

## Code style

Code comments, documentation, diagnostics, and command-line help are written
in English. User-facing localized content is added explicitly rather than
mixed into implementation comments.
