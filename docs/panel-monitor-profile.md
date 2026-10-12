# Monitorabhängige Panelgrößen auf Pegasus4

Die Zuordnung erfolgt über die EDID-basierten autorandr-Profile:

| Profil         | Höhe     | Schrift | Abstand  |
| -------------- | -------- | ------- | -------- |
| `ioc-27m2u-4k` | 40 Pixel | 17      | 40 Pixel |
| `lg-hdr-wqhd`  | 30 Pixel | 15      | 30 Pixel |
| sonstige       | 30 Pixel | 15      | 30 Pixel |

Die Schriftgröße gilt für Text und Icons, der Abstand für den oberen
Fensterrand. Unbekannte, nicht erkannte oder mehrdeutige Profile verwenden die
Zeile „sonstige“.

`lib/panel-profile.sh` enthält die Zuordnung. Das Pegasus4-Hostprofil verwendet
dieselben Werte für den Fensterabstand, auch beim Einblenden über das
Tastenkürzel. Ikarus2 bleibt bei seiner bisherigen Konfiguration.

`bin/sliverbar-refresh.sh` übernimmt die gewählte Höhe und beide Schriftgrößen
in eine generierte Konfiguration unter
`$XDG_RUNTIME_DIR/bspwm/sliverbar-<DISPLAY>/panel.conf`.
Grundlage bleibt die normale Sliverbar-Konfiguration beziehungsweise die im
Hostprofil ausgewählte Datei. Schriftfamilien, Farben, Module und sonstige
Einstellungen werden beibehalten. Die Basisdatei wird nicht umgeschrieben.
Änderungen an der Basisdatei werden beim nächsten Refresh übernommen.

Der Helfer wird beim Sitzungsstart und aus dem autorandr-Postswitch-Hook
aufgerufen. Der Resume-Watcher in
`~/.config/systemd/user/scripts/autorandr-resume-watch` ruft ihn nach jedem
erfolgreichen Profilabgleich zusätzlich auf, weil autorandr bei
`Config already loaded` seine Hooks überspringt. Nach Änderungen am Watcher
muss dessen Benutzerdienst neu gestartet werden.

Vor dem Neustart wird die erzeugte Konfiguration mit Sliverbar geprüft.
Gleiche Konfiguration und identischer laufender Prozess führen zu keinem
Neustart. Gleichzeitige Aufrufe werden gesperrt. Ein ausgeblendetes Panel behält
den Fensterabstand null und wird nach einer Größenänderung wieder ausgeblendet.
Andere Displays und explizit anders konfigurierte Panelprozesse werden nicht
beendet. Ein nicht reagierendes Panel wird nicht zwangsweise beendet; der Helfer
meldet den Fehler und kann beim nächsten Aufruf erneut versuchen abzugleichen.

Systemtray-Symbole sind keine Schriftzeichen. Sliverbar 0.12.6 bestimmt ihre
Höhe weiterhin als Panelhöhe minus zwei Pixel, also 38 beziehungsweise 28 Pixel.

## Prüfung

`tests/sliverbar-profile.py` verwendet ein separates Xvfb mit der installierten
Sliverbar. Die Tests prüfen die tatsächliche X11-Panelhöhe, Schriftwerte,
Fensterabstand, Profilwechsel, unveränderte Basisdatei, wiederholte und
gleichzeitige Aufrufe, ungültige Konfigurationen, ausgeblendete Panels,
Hostabgrenzung und den Watcher-Pfad bei bereits geladenem Monitorprofil.

Beispiel im vorhandenen Testcontainer, ausgeführt aus `~/.config/bspwm`:

```bash
docker run --rm --init --entrypoint python3 \
  -v "$HOME/.config:/config:ro" \
  -v "$HOME/.local/bin/sliverbar:/opt/sliverbar:ro" \
  sliverbar-dev:latest /config/bspwm/tests/sliverbar-profile.py \
  /opt/sliverbar /config/systemd/user/scripts/autorandr-resume-watch
```

Diese isolierten Prüfungen ersetzen keinen physischen Monitorwechsel und
keinen tatsächlichen Suspend-/Resume-Test.
