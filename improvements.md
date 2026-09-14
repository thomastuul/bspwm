# Verbesserungen der Host-Konfiguration

> Historische Analyse vom 13. September 2026. Seitdem wurden Teile der
> Vorschläge in Commit `3188379` umgesetzt. Den Umsetzungsstand beschreibt
> [docs/host-improvements.md](docs/host-improvements.md). Die folgenden Befunde
> und Prüfergebnisse dokumentieren den damaligen Zustand.

Stand: 13. September 2026. Grundlage ist eine lokale, lesende Analyse mit
Schwerpunkt auf `hosts/Ikarus2/`, `hosts/Pegasus4/` und den konsumierenden
Sitzungsskripten. Die Vorschläge zu den neun Findings sind noch nicht umgesetzt.
Eine später durchgeführte Berechtigungsänderung ist im Maßnahmenplan vermerkt.
Bei der ursprünglichen Analyse wurden externe Systemkonfigurationen und die
laufende Desktop-Sitzung nicht überprüft. Für Finding 9 wurden anschließend der
Desktop aufgenommen und die externe Conky-Konfiguration gelesen. Vor
Systemänderungen ist die in `AGENTS.md` verlangte Recherche in offiziellen
Distributionsdokumentationen und Bugtrackern nachzuholen.

## Aktueller Aufbau

Verbindlicher Umfang laut Nutzer: Es gibt ausschließlich die Hosts `Ikarus2` und
`Pegasus4`. Abweichende Hostnamen sind darauf zu prüfen, ob einer dieser beiden
Namen gemeint ist. Sie begründen keine Unterstützung zusätzlicher Hosts. Die
unten beschriebenen generischen Rückfälle sind Beobachtungen des bisherigen
Codes und keine Anforderung an das gewünschte Verhalten.

[`lib/host-profile.sh`](lib/host-profile.sh) verwendet `BSPWM_HOST_OVERRIDE`
oder den kurzen Hostnamen, setzt gemeinsame Standardwerte und lädt anschließend
`hosts/<Rechnername>/profile.sh`. Für Ikarus2 und Pegasus4 wird die Schreibweise
normalisiert. Optional kann ein Profil `SLIVERBAR_CONFIG` setzen; andernfalls
wird eine vorhandene `hosts/<Rechnername>/sliverbar.conf` ausgewählt.

| Einstellung                                  | Ikarus2                                              | Pegasus4         |
| -------------------------------------------- | ---------------------------------------------------- | ---------------- |
| Rolle                                        | `laptop`                                             | `desktop`        |
| Hintergrund unter `$HOME/Bilder/Wallpaper/`  | `sixtinische-haende-unicode-wallpaper-3840x1600.png` | `Background.jpg` |
| Oberer Abstand                               | 25 Pixel                                             | 25 Pixel         |
| Sliverbar, Conky, Blueman, Nextcloud, Picom  | aktiviert                                            | aktiviert        |
| Bildschirmsperre und automatische Ruheaktion | aktiviert                                            | aktiviert        |
| `sliverbar.conf` im Hostverzeichnis          | nicht vorhanden                                      | nicht vorhanden  |

`BSPWM_HOST_ROLE` ist in den untersuchten Sitzungsskripten nur beschreibende,
exportierte Information. Daraus werden keine weiteren Einstellungen abgeleitet.

## 1. Veraltete Profiltests

- **Befund:** [`tests/host-profile.sh`](tests/host-profile.sh), Zeilen 25–26,
  erwartet für `ikarus` ein Laptop-Profil namens `Ikarus` und für `Ikarus2`
  ebenfalls den Namen `Ikarus`. Der Loader kennt nur `Ikarus2`; `ikarus` und
  `Ikarus` erhalten generische Standardwerte. Auch die spätere Testvorbereitung
  verwendet noch `BSPWM_HOST_OVERRIDE=Ikarus`.
- **Auswirkung:** Der Test bricht bereits bei der ersten Prüfung ab.
  Nachfolgende Prüfungen werden dadurch nicht ausgeführt.
- **Vorschlag:** Die alten Testbezeichnungen `ikarus` und `Ikarus` im Kontext
  prüfen und auf `Ikarus2` korrigieren. Keine zusätzlichen Hosts oder Aliasse
  daraus ableiten. Beide gültigen Namen einschließlich Schreibungsvarianten,
  Hintergrundbilder, optionale Panel-Konfigurationen und die Behandlung
  ungültiger Namen testen.

## 2. Laptop-Monitorlogik außerhalb der Host-Weiche

- **Befund:** [`bin/autorandr-postswitch.sh`](bin/autorandr-postswitch.sh), ab
  Zeile 134, verbindet `mobile`, `dock-open` und `dock-closed` fest mit `eDP-1`
  und `HDMI-1`. Eine Prüfung auf Ikarus2 oder die Rolle `laptop` fehlt. Die
  Monitorentfernungsregeln in [`bspwmrc`](bspwmrc), Zeilen 41–42, gelten
  ebenfalls für beide Rechner.
- **Auswirkung:** Rechnerspezifische Monitorannahmen sind nicht vollständig
  unter `hosts/` gekapselt. Ob Pegasus4 betroffen ist, hängt von der dortigen
  autorandr-Einbindung und den verwendeten Profilen ab; dies wurde nicht
  geprüft.
- **Vorschlag:** Zunächst die tatsächliche Hook-Einbindung und Monitorverwaltung
  beider Rechner prüfen. Anschließend erforderliche Monitorzuordnungen und
  Unterschiede explizit konfigurieren und die vorgesehenen autorandr-Mechanismen
  bevorzugen. Änderungen müssen die Fensterübernahme beim Abdocken erhalten.

## 3. AUTOLOCK bezeichnet eine automatische Suspend-Aktion

- **Befund:** [`autostart`](autostart), ab Zeile 208, startet bei aktiviertem
  `BSPWM_ENABLE_AUTOLOCK` einen `xautolock`, der nach 30 Minuten Inaktivität
  `systemctl suspend-then-hibernate` ausführt. Das ist für beide Rechner
  aktiviert. Die Bildschirmsperre wird separat über `BSPWM_ENABLE_SCREEN_LOCK`
  gestartet. Die `xset`- und DPMS-Zeiten in Zeilen 193–195 werden unabhängig
  davon gesetzt.
- **Auswirkung:** Der Schaltername beschreibt die tatsächliche Aktion ungenau.
  Pegasus4 erhält dieselbe Ruheaktion wie der Laptop. Das Deaktivieren der
  beiden Schalter deaktiviert nicht gleichzeitig die separat gesetzten
  DPMS-Zeiten.
- **Vorschlag:** Bedeutung und Zusammenspiel dokumentieren; gewünschte
  Inaktivitätsaktionen je Rechner festlegen. Bei einer Umbenennung bestehende
  Profilkonfigurationen berücksichtigen. Vor Änderungen die tatsächlichen
  Systemdienste und Energieeinstellungen auf Wechselwirkungen prüfen.

## 4. Deaktivierte Dienste werden nicht nachträglich beendet

- **Befund:** [`autostart`](autostart) prüft Feature-Schalter vor dem Start,
  enthält aber keine entsprechende Beendigung bereits laufender Dienste nach dem
  Deaktivieren eines Schalters.
- **Auswirkung:** Ein erneuter Autostart-Aufruf überträgt eine Profiländerung
  nicht vollständig auf eine bestehende Sitzung.
- **Vorschlag:** Dokumentieren, dass solche Änderungen einen gezielten
  Dienststopp oder eine neue Sitzung erfordern. Falls eine Übernahme während der
  Sitzung gewünscht ist, zunächst vorhandene Dienstverwaltungsmechanismen prüfen
  und Zuständigkeiten für Start und Stopp eindeutig festlegen.

## 5. Panel-Tastenkürzel überschreibt den konfigurierten Abstand

- **Befund:** [`bspwmrc`](bspwmrc), Zeile 49, verwendet `BSPWM_TOP_PADDING`.
  [`sxhkd/sxhkdrc`](sxhkd/sxhkdrc), Zeilen 150–151, setzt beim Einblenden des
  Panels dagegen fest 25 Pixel.
- **Auswirkung:** Ein künftig abweichender Hostwert geht bei diesem Tastenkürzel
  verloren. Mit den derzeitigen Standardwerten ist kein Unterschied sichtbar.
- **Vorschlag:** Beim Einblenden denselben konfigurierten Abstand verwenden und
  sicherstellen, dass der Wert auch im Kontext des Tastenkürzels verfügbar ist.

## 6. Gültige Hostnamen und Umgang mit abweichenden Namen präzisieren

- **Befund:** Die [`README.md`](README.md) beschreibt die Host-Auswahl allgemein
  als unabhängig von Groß-/Kleinschreibung. Der Loader normalisiert aber nur
  Ikarus2 und Pegasus4; weitere Namen werden unverändert als Verzeichnisname
  verwendet.
- **Auswirkung:** Altbezeichnungen oder Tippfehler können unbemerkt auf
  generische Standardwerte zurückfallen und dadurch die Einstellungen des
  eigentlich gemeinten Rechners verlieren. Zusätzliche Hostprofile sind nicht
  vorgesehen.
- **Vorschlag:** Ausschließlich Ikarus2 und Pegasus4 als gültige Namen
  dokumentieren. Andere Bezeichnungen im Repository anhand ihres Kontexts prüfen
  und bei eindeutiger Zuordnung korrigieren. Nicht eindeutig zuordenbare Namen
  zur Klärung festhalten, statt sie automatisch einem Rechner zuzuweisen.

## 7. SLIVERBAR_CONFIG aus der Umgebung wird zurückgesetzt

- **Befund:** [`lib/host-profile.sh`](lib/host-profile.sh), Zeile 32, setzt
  `SLIVERBAR_CONFIG` zunächst auf einen leeren Wert. Eine Zuweisung im
  Hostprofil oder die optionale Datei im Hostverzeichnis wird anschließend
  berücksichtigt.
- **Auswirkung:** Ein vor dem Laden exportierter Wert wird nicht als Override
  übernommen. Dies ist eine Einschränkung der Schnittstelle, kein nachgewiesener
  Verstoß gegen die aktuelle Dokumentation, die die Zuweisung im Profil
  beschreibt.
- **Vorschlag:** Die gewünschte Priorität von Umgebungswert, Hostprofil und
  Standardkonfiguration ausdrücklich dokumentieren. Falls Umgebungs-Overrides
  gewünscht sind, deren Vorrang implementieren und testen.

## 8. Dokumentierter Lemonbar-Fallback fehlt im Checkout

- **Befund:** [`README.md`](README.md) und `AGENTS.md` beschreiben `lemonbar/`
  als Bash-Implementierung und Fallback. Im untersuchten Checkout ist dieser
  Ordner nicht vorhanden; auch die abgefragte Git-Dateiliste enthält ihn nicht.
- **Auswirkung:** Die dokumentierten Aufrufe von `lemonbar/start.sh` und die
  Konfiguration über `lemonbar/config.sh` sind hier nicht verfügbar.
- **Vorschlag:** Klären, ob der Fallback weiterhin vorgesehen ist. Entweder
  seine Bereitstellung dokumentieren und wiederherstellen oder die überholten
  Dokumentationsstellen aktualisieren.

## 9. Conky behält nach Monitorwechsel eine unpassende Geometrie

- **Bestätigter Befund:** Screenshot des freien Desktops 4 auf Ikarus2 am 13.
  September 2026 aufgenommen und visuell geprüft. `xrandr --query` meldet
  `HDMI-1` als primären aktiven Monitor mit `3840x1600+0+0`; `eDP-1` ist
  angeschlossen, aber nicht aktiv. `xwininfo -root -tree` zeigt das Fenster
  `conky (Ikarus2)` mit `1901x155+10+919`. Conky liegt somit deutlich oberhalb
  des unteren Bildschirmrands und erstreckt sich nur über etwa die halbe Breite.
  Zwischen Fensterunterkante und Bildschirmunterkante liegen etwa 526 Pixel.
- **Einordnung:** Position und Breite sind mit einer zuvor verwendeten
  1920×1080-Anzeige vereinbar. Der Monitorwechsel selbst wurde nicht
  reproduziert; die genaue vorherige Ereignisfolge ist damit nicht bewiesen.
- **Ursache im Integrationspfad:** Der externe Launcher
  `/home/thomas/.config/conky/start-conky.sh` ermittelt beim Aufruf Monitorgröße
  und DPI, erzeugt daraus eine Konfiguration und startet Conky neu. Das Template
  `/home/thomas/.config/conky/conky.conf.template` enthält bereits
  `alignment = 'bottom_left'`. Der gemeinsame autorandr-Hook aktualisiert jedoch
  nur die bspwm-Geometrie und ruft `autostart` nur auf, wenn Sliverbar nicht
  läuft. Eine eigenständige Aktualisierung von Conky fehlt dort. Bei laufender
  Sliverbar löst dieser Pfad daher keine Neuberechnung des Conky-Layouts aus.
- **Sollzustand:** Conky bleibt nach Wechsel von Monitor, Auflösung oder
  Topologie am unteren Rand des vorgesehenen aktiven Monitors. Breite, Spalten
  und Skalierung entsprechen dessen aktueller Geometrie.
- **Nachweis:** Temporärer Screenshot:
  `/tmp/conky-inspection.3ZXvT6/desktop-4.png` (nicht dauerhaft versioniert).
  Nach der Aufnahme wurde der vorher aktive Desktop 1 wiederhergestellt. Es
  wurden weder Monitore umgeschaltet noch Conky oder Sliverbar neu gestartet.

## Maßnahmenplan: konkrete Änderungen und Abnahme

Dieser Abschnitt beschreibt die geplante Umsetzung, nicht bereits ausgeführte
Arbeiten. Ziel ist, bestehendes Verhalten zunächst zu erhalten und Unterschiede
zwischen den Rechnern ausdrücklich nachvollziehbar zu machen. Vor Codeänderungen
ist gemäß `AGENTS.md` der Arbeitsbranch zu bestätigen; Systemänderungen
erfordern zusätzlich die dort vorgegebene Recherche und Prüfung der
tatsächlichen Umgebung.

### 1. Profiltests mit dem aktuellen Rechnernamen synchronisieren

In `tests/host-profile.sh` die Erwartungen und Testvorbereitung auf `Ikarus2`
umstellen. Die im selben Test verwendeten Bezeichnungen `ikarus` und `Ikarus`
als alte Verweise auf Ikarus2 bereinigen. Die vorhandenen Prüfungen für
Pegasus4, Feature-Schalter und den Export der Panel-Konfiguration erhalten. Die
tatsächlichen Profilunterschiede anhand von Rolle und Hintergrundpfad prüfen;
die Auswahl einer optionalen Panel-Datei mit isolierten Testdaten abdecken.

Abnahme: Die vollständige Profiltestsuite erreicht ihr Ende erfolgreich. Beide
gültigen Namen funktionieren auch in abweichender Groß-/Kleinschreibung.
Ungültige Namen werden als eigene Fehlerfälle entsprechend der unter Maßnahme 6
festzulegenden Behandlung geprüft, nicht als unterstützte zusätzliche Rechner.

### 2. Monitorzuordnungen und Hook-Zuständigkeit explizit machen

Zuerst auf beiden Rechnern die vorhandenen autorandr-Profile,
Hook-Verknüpfungen, Ausgangsnamen und die Reihenfolge von Sitzungsstart und
Profilwechsel erfassen. Anhand offizieller Dokumentation und bekannter Fehler
prüfen, welche Aufgaben autorandr und bspwm bereits regulär übernehmen. Den
bestehenden Hook nur für nachweislich darüber hinaus notwendige Aufgaben
beibehalten.

Falls die gemeinsame Hook-Logik benötigt bleibt, die Ikarus2-spezifischen
Ausgangsnamen aus `bin/autorandr-postswitch.sh` in dessen Hostprofil verlagern.
Die Konsolidierung nur bei ausdrücklich konfigurierter Monitorzuordnung
ausführen. Einstellungen zur Monitorentfernung in `bspwmrc` erst nach Prüfung
ihrer Auswirkungen je Host parametrisieren; bisherige Werte bis dahin erhalten.
Die tatsächliche Installation der autorandr-Profile und des Hooks in `README.md`
mit Zuständigkeit und Rückbau dokumentieren.

Abnahme: Auf Ikarus2 funktionieren `mobile`, `dock-open` und `dock-closed`
einschließlich Fensterübernahme und wiederholter Wechsel. Pegasus4 übernimmt
keine unpassenden Laptop-Zuordnungen. Diese Abnahme benötigt einen gesonderten
Laufzeittest; sie ist durch die bisherige Quellcodeanalyse nicht erfüllt.

### 3. Inaktivitätsverhalten eindeutig benennen und dokumentieren

In `README.md` die drei vorhandenen Mechanismen getrennt erklären:
Bildschirmsperre, DPMS und automatische Suspend-Aktion. Für jeden Mechanismus
Schalter, Zeitwerte und ausgeführten Befehl angeben. Dabei ausdrücklich
festhalten, dass aktuell beide Rechner nach 30 Minuten `suspend-then-hibernate`
anfordern.

Soll der Schalter umbenannt werden, beispielsweise in
`BSPWM_ENABLE_AUTOSUSPEND`, Loader und `autostart` gemeinsam anpassen. Den
bisherigen Namen über eine dokumentierte Übergangsregel unterstützen und den
Vorrang bei widersprüchlichen Angaben festlegen. Zeitwerte und Aktionen nur dann
je Host ändern, wenn das gewünschte Verhalten geklärt und die Wechselwirkung mit
vorhandenen Systemdiensten geprüft ist. Aus der Rolle `desktop` allein keine
Deaktivierung ableiten.

Abnahme: Die Standardkonfiguration behält ihr bisheriges Verhalten. Bei einer
Umbenennung zusätzlich alte und neue Profilangaben sowie Konfliktfälle testen.
Geänderte Energieaktionen anschließend auf dem betreffenden Rechner
verifizieren.

### 4. Gültigkeit von Feature-Änderungen festlegen

In `README.md` beschreiben, dass Feature-Schalter zunächst den Dienststart
steuern. Für die Übernahme deaktivierter Features eine neue Sitzung als
einfachen Weg angeben; ein gezielter Stopp muss den tatsächlich zuständigen
Prozess oder Dienst berücksichtigen. Ebenso erläutern, dass bereits laufende
Programme nicht allein durch erneutes Aufrufen von `autostart` neu konfiguriert
werden.

Nur falls eine Änderung innerhalb der laufenden Sitzung erforderlich ist,
vorhandene Dienstverwaltung auf ihre Eignung prüfen. Dann Start, Stopp und
Neustart pro Komponente eindeutig zuordnen, ohne parallele Verwaltungswege
einzuführen. Keine pauschalen Prozessabbrüche als Bestandteil des normalen
Autostarts ergänzen.

Abnahme: Die Dokumentation unterscheidet Sitzungsstart und nachträgliche
Übernahme. Eine gegebenenfalls ergänzte Laufzeitverwaltung stoppt ausschließlich
die von ihr verwalteten Dienste und erzeugt bei wiederholtem Aufruf keine
Doppelstarts.

### 5. Den Panel-Abstand auch im Tastenkürzel aus dem Profil beziehen

In `sxhkd/sxhkdrc` den festen Wert `25` beim Einblenden durch den ausgewählten
Profilwert ersetzen. Dazu den Loader in einem expliziten Bash-Aufruf laden und
anschließend `BSPWM_TOP_PADDING` an `bspc` übergeben. Den Konfigurationspfad wie
in `bspwmrc` aus `XDG_CONFIG_HOME` beziehungsweise `$HOME/.config` bestimmen. So
funktioniert die Auswahl auch bei separat gestartetem sxhkd, ohne auf einen
zufällig geerbten Variablenwert angewiesen zu sein.

Abnahme: Mit einem isolierten Profilwert ungleich 25 und einem ersetzten
`bspc`-Aufruf prüfen, welcher Wert übergeben wird. Danach Ein- und Ausblenden in
einer freigegebenen visuellen Sitzung prüfen; Bash- und C-Panel dürfen dabei
nicht gleichzeitig laufen.

### 6. Hostbezeichnungen prüfen und auf die zwei gültigen Namen begrenzen

In `README.md` ausschließlich `Ikarus2` und `Pegasus4` als unterstützte Hosts
aufführen. Platzhalter für beliebige weitere Hostprofile durch die beiden
tatsächlichen Verzeichnisse ersetzen. Die vorhandene Normalisierung der
Groß-/Kleinschreibung für diese Namen erhalten.

Hostbezeichnungen in Konfiguration, Skripten, Tests und Dokumentation gezielt
suchen. Abweichende Namen anhand der umgebenden Einstellungen und nötigenfalls
der lokalen Git-Historie einem gültigen Namen zuordnen. Eindeutige Altverweise
korrigieren; unklare Zuordnungen dokumentieren und klären. Historische Befunde
und absichtliche ungültige Testeingaben als solche kennzeichnen.

Für einen zur Laufzeit ungültigen Hostnamen eine ausdrückliche Diagnose
vorsehen. Vor einer Änderung festlegen, ob der Loader danach abbricht oder eine
gemeinsame Notkonfiguration verwendet, und die Auswirkungen auf den
Sitzungsstart prüfen. Keine automatische unscharfe Zuordnung und keine
allgemeine Suche nach weiteren Hostprofilen ergänzen.

Abnahme: Aktive Hostverweise nennen nur die beiden gültigen Rechner.
Dokumentation und Profiltests stimmen hinsichtlich Normalisierung und Behandlung
ungültiger Namen überein. Abweichende Fundstellen sind korrigiert oder
ausdrücklich als historische beziehungsweise negative Testfälle erklärt.

### 7. Priorität der Panel-Konfiguration festschreiben

In `README.md` zunächst die vorhandene Reihenfolge dokumentieren: Zuweisung im
Hostprofil, andernfalls vorhandene `sliverbar.conf` im Hostverzeichnis,
andernfalls Sliverbars normale Suche. Ausdrücklich erwähnen, dass ein vor dem
Laden gesetzter Umgebungswert derzeit verworfen wird.

Falls ein Umgebungs-Override gewünscht ist, dessen Vorrang separat festlegen und
im Loader umsetzen. Dabei berücksichtigen, dass `bspwmrc` und `autostart` den
Loader nacheinander in verschiedenen Prozessen laden und
Panel-Konfigurationswerte vererbt werden können. Ein geerbter Profilwert darf
bei einem expliziten Hostwechsel nicht unbemerkt als benutzerdefinierter
Override behandelt werden.

Abnahme: Die dokumentierte Priorität einschließlich leerer Werte, fehlender
Panel-Datei und Laden in einem Kindprozess mit abweichendem Host testen.

### 8. Den dokumentierten Fallback mit dem Checkout abgleichen

Zunächst anhand der lokalen Git-Historie und Projektabsicht klären, ob Lemonbar
weiterhin bereitgestellt werden soll. Wenn ja, den vorgesehenen Bezugs- und
Installationsweg ermitteln und dokumentieren; die bisherige Implementierung
nicht ohne Grundlage nachbauen. Wenn nein, die überholten Pfade und
Startanweisungen in `README.md` sowie die entsprechenden Projektangaben in
`AGENTS.md` aktualisieren. Verbliebene Lemonbar-Verweise im Autostart auf ihre
tatsächliche Verwendung prüfen, bevor zugehörige Laufzeitverzeichnisse oder
Variablen entfernt werden.

Abnahme: Jeder dokumentierte Einstiegspunkt existiert entweder im Checkout oder
hat einen nachvollziehbaren Installationsweg. Ein wieder bereitgestellter
Bash-Fallback wird nur getrennt von Sliverbar getestet.

### 9. Conky nach Monitor- und Auflösungswechsel aktualisieren

Vor der Umsetzung anhand der offiziellen Conky- und Distributionsdokumentation
sowie der Bugtracker prüfen, wie Conky RandR-Änderungen und eine geänderte
Konfiguration regulär übernimmt. Die vorhandene autorandr-Hook-Einbindung auf
Ikarus2 und gegebenenfalls Pegasus4 sowie ihre tatsächliche Aufrufreihenfolge
prüfen. Der bereits bestätigte Fehler betrifft nicht eine fehlende
`bottom_left`-Einstellung, sondern die Anpassung der laufenden Anzeige.

Sofern die regulären Conky-Einstellungen die Anpassung einschließlich der im
Launcher erzeugten Spaltenbreiten nicht abdecken, die bestehende Integration
gezielt ergänzen: Nach abgeschlossener Monitorumschaltung die
Conky-Konfiguration für den vorgesehenen aktiven Monitor neu erzeugen und über
den dokumentierten Mechanismus laden beziehungsweise die verwaltete
Conky-Instanz neu starten. Dies unabhängig vom Zustand der Sliverbar und unter
Beachtung von `BSPWM_ENABLE_CONKY` auslösen. Nicht den gesamten Autostart nur
wegen Conky wiederholen. Den bestehenden Launcher nach Prüfung wiederverwenden;
keinen zusätzlichen dauerhaften Monitor-Watcher ohne nachgewiesenen Bedarf
einführen.

Vor einer Wiederverwendung dessen bisheriges `pkill -x conky` prüfen und die
Neuladung beziehungsweise Beendigung auf die verwaltete Instanz begrenzen.
Schnelle aufeinanderfolgende Profilwechsel dürfen keine konkurrierenden
Konfigurationsschreibvorgänge oder Doppelstarts verursachen. Bei mehreren
aktiven Monitoren die Zielauswahl ausdrücklich festlegen und auch
Monitorversätze berücksichtigen, nicht nur Breite und Höhe. Das externe Template
und der Launcher liegen außerhalb dieses Repositorys; Änderungen und Rückbau
dort separat erfassen.

Abnahme: Auf Ikarus2 Wechsel zwischen interner 1920×1080-Anzeige und externem
3840×1600-Monitor sowie `dock-open` und `dock-closed` prüfen. Nach jedem Wechsel
Fenstergeometrie und einen Screenshot eines freien Desktops vergleichen:
Unterkante mit vorgesehenem Abstand zum Zielmonitor, angepasste Breite und
lesbare, vollständige Spalten. Zusätzlich wiederholte Wechsel, laufende
Sliverbar und deaktiviertes Conky berücksichtigen. Tests auf Pegasus4 anhand
seiner tatsächlichen Monitoranordnung durchführen. Der bisherige Screenshot ist
nur der Fehlernachweis, kein bestandener Korrekturtest.

### Bereits erledigt: Ausführungsrecht von Pegasus4 entfernen

Auf ausdrücklichen Wunsch wurde `hosts/Pegasus4/profile.sh` mit `chmod a-x` von
seinen Ausführungsrechten befreit. Der auf dem Host bestätigte Modus ist `664`
(`rw-rw-r--`); Git zeigt die Änderung von `100755` auf `100644`. Der Dateiinhalt
blieb unverändert. Beide Profile benötigen nur Leserechte, weil der Loader sie
mit `source` in die aufrufende Shell einliest.

Diese Änderung vereinheitlicht die Ausführbarkeit, nicht notwendigerweise alle
Leseschreibrechte. Ein Rückbau ist mit `chmod a+x hosts/Pegasus4/profile.sh`
möglich; damit wird der zuvor beobachtete Modus `775` wiederhergestellt. Die
Host-Abfrage bestätigte die Entfernung der Ausführungsrechte; `git diff --check`
bestand.

### Reihenfolge, Prüfungen und Rückbau

Zunächst die Profiltests reparieren und die verhaltenserhaltenden
Dokumentationskorrekturen umsetzen. Danach den Panel-Abstand vereinheitlichen.
Monitor- und Energieänderungen erst auf Grundlage der Rechnerprüfung und der
vorgeschriebenen Recherche durchführen. Die Prüfung abweichender
Hostbezeichnungen gehört zur Bereinigung; zusätzliche Hosts sind nicht
vorgesehen. Optionale Erweiterungen für Umgebungs-Overrides und laufende
Dienstverwaltung sind getrennte Entscheidungen und keine Voraussetzung für die
Dokumentationskorrekturen.

Für jede geänderte Shell-Datei `bash -n` und ShellCheck über das offizielle
Docker-Image `koalaman/shellcheck:stable` mit schreibgeschützt eingebundenem
Repository ausführen. Betroffene Verhaltenstests sowie `git diff --check`
ergänzen; Laufzeit- und visuelle Prüfungen nur dann als bestanden
protokollieren, wenn sie tatsächlich ausgeführt wurden. Für reine
Dokumentationsänderungen Verweise, inhaltliche Konsistenz und Whitespace prüfen.

Jede umgesetzte Maßnahme mit betroffenen Dateien, vorherigen Werten,
ausgeführten Prüfungen und erforderlichem Neustart dokumentieren. Änderungen
getrennt halten, damit sie auf dem bestätigten Arbeitsbranch gezielt rückgängig
gemacht werden können. Für externe Konfigurationen zusätzlich den konkreten
Rückbauweg und die vorherige Hook- beziehungsweise Dienstkonfiguration
festhalten.

## Durchgeführte Prüfungen und Grenzen der ursprünglichen Analyse

- `bash -n` für `bspwmrc`, `autostart`, `lib/host-profile.sh`,
  `hosts/Ikarus2/profile.sh`, `hosts/Pegasus4/profile.sh`,
  `bin/autorandr-postswitch.sh` und `tests/host-profile.sh`: alle bestanden.
- Isoliertes Laden mit bereinigter Umgebung für `Ikarus2`, `IKARUS2`,
  `Pegasus4`, `PEGASUS4`, `Ikarus` und `unknown-host`: beide vorhandenen
  Rechnerprofile einschließlich Großschreibungsvarianten bestätigt; die letzten
  beiden Namen erhalten generische Werte. Rolle, Abstand, AUTOLOCK-Schalter,
  Hintergrundpfad und leere Panel-Konfigurationsauswahl wurden ausgegeben.
- `bash -x tests/host-profile.sh`: fehlgeschlagen, Exit-Code 1, bei der ersten
  veralteten Erwartung. Die restliche Testsuite lief dadurch nicht durch.
- Keine Dienste gestartet, keine Konfiguration geändert, keine Laufzeit- oder
  visuellen Tests durchgeführt. ShellCheck und C-Buildtests waren nicht Teil
  dieser lesenden Analyse.
- Die tatsächliche autorandr-Konfiguration außerhalb dieses Ordners,
  Dienstreihenfolge, installierte Programme und Existenz der Hintergrundbilder
  wurden nicht validiert. Aussagen zu Auswirkungen auf eine laufende Sitzung
  sind daher auf das aus dem Code ableitbare Verhalten begrenzt.
- Bei der Analyse stand der Checkout auf `master`; Git meldete einen bereits
  veränderten Zustand für das Submodul `sliverbar`. Dieser blieb unangetastet.
