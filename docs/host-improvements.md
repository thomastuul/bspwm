# Host configuration implementation record

Date: 2026-09-13. Input: `improvements.md`. Working branch:
`dev/host-profile-improvements`, selected under the user's explicit branch
creation authorization. The pre-existing Pegasus4 mode change and Sliverbar
submodule revision were excluded from implementation commits.

## Decisions and changes

| Measure | Implementation | Previous behavior / rollback scope |
|---|---|---|
| 1 | `tests/host-profile.sh`: valid names, spelling variants, wallpapers, features, isolated panel priority and child-host changes | Stale Ikarus expectations stopped the suite early |
| 2 | Ikarus2 declares its internal/external outputs; the autorandr hook gates consolidation on that pair | Both hosts previously used hard-coded laptop outputs; bspwm removal settings remain true/false |
| 3 | README separates screen lock, DPMS and automatic sleep | AUTOLOCK name, 30-minute sleep command and all time values retained; no migration necessary |
| 4 | README explains start-only switches and new-session application | No new general service manager or process-killing policy |
| 5 | sxhkd loads the profile in Bash and toggles padding between 0 and the profile value | The former command sequence used fixed padding 25; an explicit conditional now implements both directions |
| 6 | Loader diagnoses unknown names and uses common emergency defaults without loading their directories | Unknown names previously silently selected arbitrary directory names; legacy names remain negative tests only |
| 7 | README and tests fix the existing panel priority contract | Incoming environment value still resets; no new override interface |
| 8 | README/AGENTS describe Lemonbar as historical | Commit `0cd26fe` (#126) explicitly removed it; no invented replacement. Legacy screencast/runtime references are documented and retained |
| 9 | Shared `bin/conky-refresh.sh` generates, atomically publishes and reloads the matching Conky configuration | Autostart previously called a launcher with global `pkill`; hook only indirectly refreshed Conky when the panel was absent |

No external source, template, package, service or autorandr profile was edited.
The Conky helper uses the inspected launcher's existing generation-only contract.
It appends the target Xinerama head and a rectangle comment, so an offset change
also causes a reload when width, height and head index are otherwise unchanged.
Negative RandR offsets are rejected explicitly because the existing external
generator does not parse them correctly. All three inspected Ikarus2 profiles
use nonnegative offsets. Supporting other geometry requires fixing and testing
that external generator first; the wrapper does not silently fabricate geometry.

## Research and environment evidence

Official sources consulted before changing the integration:

- [Debian autorandr manual](https://manpages.debian.org/trixie/autorandr/autorandr.1.en.html)
  and the [upstream integration documentation](https://github.com/phillipberndt/autorandr):
  postswitch is the existing integration point after a mode change.
- [Debian bspwm manual](https://manpages.debian.org/trixie/bspwm/bspwm.1.en.html),
  local settings and the existing desktop-transfer implementation were inspected.
  No removal-policy change was inferred from a machine's role.
- [Ubuntu Conky manual](https://manpages.ubuntu.com/manpages/resolute/man1/conky.1.html)
  and the installed Conky manual document `SIGUSR1` reload and `xinerama_head`.
  These mechanisms cannot regenerate the external launcher's numeric column
  widths; generation followed by a scoped reload is therefore needed.
- [Conky discussion #2180](https://github.com/brndnmtthws/conky/discussions/2180)
  concerns primary-output versus Xinerama-head selection. The helper matches
  rectangles rather than assuming RandR and Xinerama indices agree.
- [Debian bug #1027895](https://bugs-devel.debian.org/cgi-bin/bugreport.cgi?bug=1027895)
  was found in the tracker search; full retrieval failed. It is not treated as
  proof of this installation's defect or as justification for a workaround.
- [autorandr issue #152](https://github.com/phillipberndt/autorandr/issues/152)
  concerns hook execution. Local inspection confirms the existing postswitch
  symlink; no new hook framework or permanent watcher was installed.

Local evidence on Ikarus2:

- Installed autorandr `1.15-1`, bspwm `0.9.10-3`.
- `~/.config/autorandr/postswitch` resolves to this repository's
  `bin/autorandr-postswitch.sh`.
- `mobile`: eDP-1, 1920x1080 at 0,0, primary.
- `dock-open`: eDP-1, 1920x1080 at 0,0, primary; HDMI-1, 3840x1600 at 1920,0.
- `dock-closed`: HDMI-1, 3840x1600 at 0,0, primary; eDP-1 off.
- Other existing profile directory names (`ioc-27m2u-4k`, `hdmi_profile`,
  `lg-hdr-wqhd`) identify display presets, not additional computer names.
- Packaged `autorandr.service` runs after `sleep.target`;
  `autorandr-lid-listener.service` is active and starts autorandr on lid events.
  The packaged XDG autostart entry also runs autorandr in desktop environments
  that consume it; bare bspwm's autostart does not itself process XDG entries.
- The existing external `autorandr-resume-watch.service` is active, ordered
  after `graphical-session.target`, and independently invokes autorandr.
  This is an existing overlapping management path, not a new recommendation.
  Its original necessity and both hosts' full boot event timelines are not
  established by this implementation.
- Host queries outside the process sandbox confirm xautolock with the documented
  suspend command, xss-lock with the external `audio-volume-lock-notifier`,
  saver 300/10 seconds, DPMS 400/600/900, and bspwm removal settings true/false.
  README documents the repository's default dimmer, not this environment override.
- File ownership/mode observations outside the workspace were not used as
  security findings. Pegasus4 runtime evidence is still unavailable.

## Validation

Passed:

- `bash tests/host-profile.sh`: full suite; unknown-host stderr is expected.
- `python3 tests/host-integration.py`: isolated Xvfb with real Conky and sxhkd;
  first start, reload with unchanged PID, five concurrent callers, unrelated
  Conky preservation, generator failure retaining the previous file, feature
  disablement, real key events with padding 41/0, and mocked autorandr host gate.
  Geometry fixtures also check primary selection at nonzero offsets and rejection
  of unsupported offsets without overwriting the previous config.
- `bash -n` on `autostart`, `lib/host-profile.sh`,
  `hosts/Ikarus2/profile.sh`, `bin/autorandr-postswitch.sh`,
  `bin/conky-refresh.sh`, and `tests/host-profile.sh`.
- ShellCheck on those same six files using `koalaman/shellcheck:stable`, with
  the repository mounted read-only and container networking disabled.
- Embedded Bash in the sxhkd binding: `bash -n` and the same official
  ShellCheck image (SC1091 suppressed for the runtime-resolved profile path).
- Python AST syntax and local Markdown link existence checks.
- `git diff --check`.
- Live Ikarus2 refresh on the existing HDMI-1 3840x1600 display, with Sliverbar
  running: Conky PID 9125 was preserved. Observed geometry after reload:
  `3820x172+10+1422`, leaving six pixels beneath its X window.
  Screenshot `/tmp/bspwm-conky-improvements.png` was visually inspected on an
  empty desktop: eight columns span the screen and sit at the bottom.
  The previous desktop was restored. The screenshot is temporary, not committed.

Not claimed as passed:

- Physical mobile/dock-open/dock-closed cycles and window transfer on Ikarus2,
  repeated hardware reconnects, or any Pegasus4 runtime/visual acceptance.
- Visual acceptance of the full external template on the internal 1920x1080
  display. Xvfb tests use a minimal Conky config and are not a substitute.
- Full boot sequencing on both hosts, or suspend/hibernate execution. No power
  actions or timings were changed.
- The running Codex session's initial `dev` profile could not be established
  from repository evidence. No attempt was made to switch profiles mid-session.
- C builds were not run because no C or submodule files were changed.

## Activation and rollback

The installed postswitch symlink already points into this checkout; the next
successful autorandr switch uses the changed hook automatically. Restart sxhkd
or use its existing reload shortcut to activate the padding binding. A new login
session applies feature switch changes; rerunning autostart does not stop disabled
services. The live Conky refresh above has already applied the current geometry.

Revert the implementation commit on the developer branch to restore repository
behavior. Do not reset the whole worktree: the existing Pegasus4 mode change,
Sliverbar revision and original untracked `improvements.md` belong to the user.
After rollback, reload sxhkd and start a new session. Conky's generated file under
`$XDG_RUNTIME_DIR` is transient and will be regenerated by the original launcher
on session startup. The external Conky template, Lua helper, launcher, autorandr
profiles, symlink and services need no file rollback because none were changed.

If removing autorandr integration separately, first back up the existing
`~/.config/autorandr/postswitch` symlink and the three profile directories, then
remove only those selected entries. Restore that backup to undo the removal.
Do not remove the unchanged bspwm monitor-removal settings or unrelated display
profiles as part of reverting this implementation.
