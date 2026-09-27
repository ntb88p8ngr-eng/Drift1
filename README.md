# Midnight Drift

Ein Drift-Racing-Spiel mit Godot 4.3. Strecken, Gelände, Wald, Gras, Zuschauer, Häuser, Himmel, Wetter, Texturen und
die meisten Sounds werden beim Start **prozedural im Code erzeugt**. Echte Assets sind nur die drei Automodelle
(Blend Swap), die Garage im Hauptmenü und die R34-Motor- und Turbo-Aufnahmen (siehe Credits).

## Download (.exe)

Jeder Push baut automatisch per GitHub Actions eine Windows-Version:

1. Im Repository auf **Actions → Build Midnight Drift** gehen und den neuesten Lauf öffnen.
2. Unter *Artifacts* **MidnightDrift-Windows** herunterladen und entpacken.
3. `MidnightDrift.exe` starten. Es gibt nur diese eine Datei, die Spieldaten sind eingebettet.

Für eine Release-Version pushst du einen Tag (z. B. `git tag v1.0.0 && git push --tags`). Der Workflow
hängt dann die ZIPs an ein GitHub-Release.

Zusätzlich lädt der Workflow *test-output* hoch, mit Logs und Screenshots aus einem automatischen Render-Test.

## Features

| Bereich | Umsetzung |
|---|---|
| Grafik | Forward+-Renderer, dynamische Schatten (Sonne/Mond mit bis zu 4 Kaskaden, Scheinwerfer werfen Schatten), SSAO, SSR, Glow, ACES-Tonemapping, Nebel, **Lens Flares** von Sonne (Strahlen, Halo, Geisterbilder) und Mond, die hinter Bäumen und Hügeln verschwinden |
| Grafikoptionen | Anzeigemodus (Fenster, randloses/exklusives Vollbild), Auflösung, **Kantenglättung** (FXAA, TAA, MSAA 2x/4x/8x und Kombinationen), Upscaling (Bilinear, AMD FSR 1.0/2.2) mit Schärfe, VSync, FPS-Limit, **Gamma**, Grafikqualität, Schatten, Gras-Stufe, **Sichtweite für Bäume und Pflanzen in Metern** (wirkt sofort), Lens Flares – im Hauptmenü und im Pausenmenü |
| Tageszeit | Start zur gewählten Tageszeit (Morgennebel, Mittag, Sonnenuntergang, Nacht). Optional läuft die Zeit weiter (**Tagesverlauf** 8–60 Minuten pro Tag): Die Sonne wandert, der Himmel färbt sich über Sonnenuntergang und Dämmerung zur Nacht, der Mond übernimmt, Laternen, Fenster und das Autolicht gehen automatisch an |
| Wetter | **Trocken, Regen oder wechselhaft** (Schauer kommen und gehen). Wolken ziehen vor dem Regen auf, Regentropfen mit Spritzern und eigenem Regengeräusch. Die Straße wird nass (dunkler, spiegelnd) und **rutschiger**, **Pfützen** auf der Fahrbahn sind extra rutschig, die Reifen wirbeln Gischt auf. Online sehen alle Spieler dasselbe Wetter |
| Skybox | eigener Sky-Shader mit ziehenden Wolken in zwei Schichten, Sonne, Mond und Sternen |
| Strecken | **Kurohana Ridge** (fließende Waldstrecke mit ~1,9 km) und **Harbor Drift Yard** (breiter Hafenkurs mit ~1,3 km und engen Kehren). Beide haben Curbs, Leitplanken bzw. Betonwände, ein Startportal mit Startampel, Tribüne und Straßenlaternen |
| Gelände | Höhenfeld mit Hügeln, Böschungen, Einschnitten und Bergen hinter den Leitplanken (die Fahrbahn selbst bleibt eben), Fels an steilen Hängen, Waldboden, Kies, Wiesen; im Hafen eine Beton-Vorfläche und bewaldete Hügel an Land |
| Wald & Pflanzen | **dichter Wald** überall um die Strecken (bis zu ~16.000 Bäume) mit 3 Detailstufen, dazu Büsche, kleine Sträucher, Farne und Felsen. Laub- und Nadelbäume, Herbstfärbung, Wind im Shader |
| Gras | wird nur **in der Nähe der Kamera** gezeichnet: tausende Grasbüschel in zwei Dichten, hohe Gräser und Blumen auf Wiesen, trockene Stellen, Wind, das Gras biegt sich unter dem Auto |
| Zuschauer | Zuschauergruppen an den engsten Kurven hinter Fangnetzen, mit Fahnen und Pavillons, jubeln, klatschen oder winken; die Tribüne am Start ist voll |
| Häuser | japanische Wohnhäuser, Laden mit Getränkeautomaten, Scheune, Büro, Lagerhallen, Container, Kräne, Schiffe, Skyline. Nachts leuchten die Fenster |
| Autos | **Nissan Skyline GT-R R34** (Standard), **Ford Mustang GT**, **BMW M3 GT3**: detaillierte 3D-Modelle von Blend Swap, für das Spiel optimiert. Echte Getriebeübersetzungen (R34, Mustang), Drehzahlmesser wie im echten Auto (R34 bis 9.000, Mustang bis 8.000, M3 GT3 bis 10.000 U/min). Einfarbige Klarlack-Lackierungen plus eigene Farbe |
| Hauptmenü | Das Auto dreht sich auf einer leuchtenden Plattform **mitten in einer alten Werkstatthalle** (Ziegelwände, Stahlträger, Reifenstapel, Poster), mit Studio-Softboxen und Hallenlicht |
| Tuning | Motor, Getriebe, Fahrwerk, **Lenkwinkel**, Turbo und Nitro, je 3 Stufen, für jedes Auto einzeln. Das Getriebe-Tuning ändert die Übersetzung (**längerer 2. und 3. Gang** für Drifts, schnelleres Schalten); die Garage zeigt Übersetzungen und Endgeschwindigkeit pro Gang. Bezahlt wird mit Credits aus Driftpunkten und Rennen. Dazu kostenlos umstellbar der **Burble-Tune** (Aus/Mild/Sport/Brutal): Blubbern und Knallen im Schiebebetrieb, Flammen beim Gaswegnehmen und am Begrenzer – ab Werk ist er beim Mustang aus, beim R34 mild und beim M3 GT3 auf Sport |
| Nitro | **Shift** gibt Nitro. Die blauen Flammen kommen genau aus den Endrohren. In der Serie ist der Boost klein, mit Tuning wird er stärker und hält länger |
| Launch Control | **W + S im Stand**: Die Drehzahl pendelt am Zwei-Stufen-Begrenzer (mit Fehlzündungen), die Vorderbremse hält und die Hinterräder drehen durch (Burnout). S loslassen = Start mit Radschlupf |
| Licht | Scheinwerfer mit dynamischen Spotlights (L), Bremslicht, Rückfahrlicht, Unterbodenbeleuchtung. Bei Dämmerung und Nacht schaltet sich das Licht automatisch ein |
| Physik | eigenes Raycast-Fahrwerk: Federung, Dämpfer, Stabis, Reifenmodell mit Schräglaufwinkel und Reibungskreis. Radschlupf und Handbremse lassen das Heck ausbrechen. Einstellbar: Konter-Lenkhilfe, **Stärke der Handbremse** und **seitliches Rutschen** (weichere Übergänge). Die Darstellung wird zwischen den letzten beiden Physikschritten interpoliert – kein Ruckeln bei hohem Tempo, auch bei 75/144 Hz oder schwankender Bildrate. Die Verfolgerkamera filtert Federbewegungen und Ruckler beim Gasgeben und Bremsen (**Kamera-Glättung** einstellbar) |
| Getriebe | alle Autos starten mit **Automatik** (schaltet auch bei durchdrehenden Rädern ohne Pendeln). **Manuell** lässt sich jederzeit in der Garage oder beim Fahren mit **M** umschalten |
| Sound | **R34 mit echten Aufnahmen**: Vollgas aus einem Prüfstandslauf, Schiebebetrieb vom HKS-Auspuff, echtes Turbopfeifen (leise) und Blow-off „pssst“ mit Flattern beim Gaswegnehmen. Mustang: Cross-Plane-V8 mit zwei Zylinderbänken, die in ungleichen Abständen zünden (tiefes Blubbern statt Kreischen). M3 GT3: Renn-V8 mit Getriebesingen und Zündunterbrechung beim Hochschalten, tief abgestimmt. Die Motoren sind im Mix bewusst zurückgenommen (Lautstärke zusätzlich im Audio-Menü). Fehlzündungen sind tiefe, dumpfe Knaller statt Zischen. Dazu Reifenquietschen, Wind, Regen, Aufprall |
| Effekte | Reifenrauch, Staub auf Gras bzw. Beton, Gischt bei Nässe, Bremsspuren, Flammen aus dem Auspuff |
| Driftpunkte | Winkel × Geschwindigkeit × Zeit, Combo-Multiplikator (bis x6), Bonus für Richtungswechsel und für Driften nah an der Wand. **360°-Bonus** (volle Drehung mit durchgehend durchdrehenden Reifen auf der Strecke) und **Reverse-Entry-Bonus** (mit über 100° Winkel rückwärts in die Kurve und abgefangen). Wandkontakt oder Offroad kostet die Combo. Oben der **Drift-Score**, links der **Top-Drift** (bester Einzeldrift – online von allen Spielern) |
| Leaderboard | lokal pro Strecke: Driftpunkte, bester Einzeldrift, beste Runde, Rennzeit (Top 10). Im Rennen zeigt **Tab** die Live-Rangliste |
| Modi | Freies Driften, Rennen, Drift-Battle. Einstellbar sind 1–20 Runden, Tageszeit, Tagesverlauf, Wetter und Strecke |
| Online | Lobbys mit **Self-Hosting durch den Lobby-Ersteller** (ENet, UDP-Port 24570). Automatische Portfreigabe per UPnP, LAN-Lobby-Suche, Chat und Bereit-Status. Der Host stellt Strecke, Modus, Runden, Tageszeit und Kollisionen ein. Ergebnisse werden am Ende synchronisiert |

## Steuerung

| Taste | Aktion |
|---|---|
| W / ↑ / RT | Gas |
| S / ↓ / LT | Bremse / Rückwärts |
| A, D / ←, → / Stick | Lenken |
| Leertaste / (A) | Handbremse (mit Gas drehen die Hinterräder weiter) |
| Shift / (B) | Nitro |
| E / RB | Hochschalten (manuell) |
| Q oder Strg / LB | Runterschalten (manuell) |
| W + S im Stand | Launch Control / Burnout |
| M | Automatik ⇄ Manuell |
| C / (Y) | Kamera wechseln (Verfolger, weit, Motorhaube, Stoßstange, Dach) |
| **V** / R-Stick-Klick | **Kamera-Lock lösen**: freie Orbit-Kamera mit Maus bzw. rechtem Stick, Mausrad zoomt |
| Rechte Maustaste halten | kurz umsehen |
| B / (X) | nach hinten schauen |
| R / Back | Auto auf die Strecke zurücksetzen |
| L | Licht an/aus |
| Tab | Leaderboard / Spielerliste |
| Esc / Start | Pause |

## Online spielen

- **Host:** *Online-Modus → Lobby erstellen.* Dein PC ist der Server. Im LAN finden dich Mitspieler
  automatisch. Über das Internet klappt es, wenn UPnP den Port öffnen kann (der Status steht in der
  Lobby). Sonst gibst du im Router **UDP-Port 24570** frei (der Port ist einstellbar). Deinen
  Mitspielern gibst du deine öffentliche IP. Strecke, Modus, Runden, Tageszeit, Tagesverlauf und Wetter legt der Host fest.
- **Mitspieler:** IP und Port eingeben und *Beitreten* klicken. Alternativ die Lobby in der LAN-Liste anklicken.
- Alle klicken auf *Bereit*, dann startet der Host das Rennen. Danach geht es zurück in dieselbe Lobby.

## Selbst bauen / entwickeln

1. [Godot 4.3](https://godotengine.org/download/archive/4.3-stable/) installieren und die Export-Templates dazu.
2. `project.godot` im Editor öffnen. F5 startet das Spiel.
3. Den Export startest du über *Projekt → Exportieren → Windows Desktop*. Die Vorlage liegt in `export_presets.cfg`.

Projektstruktur:

```
scripts/autoload/  game.gd (Einstellungen, Autos, Leaderboard, Input), net.gd (Lobbys/ENet/UPnP/LAN)
scripts/car/       car.gd (Physik), car_body.gd (Modell + Lack + Licht), car_audio.gd, tire_fx.gd, camera_rig.gd
scripts/world/     world.gd (Rennablauf), track.gd, terrain.gd (Gelände), scenery.gd (Wald, Häuser, …), crowd.gd,
                   grass.gd, atmosphere.gd (Tageszeit & Wetter), lens_flare.gd, tree_factory.gd, drift_scorer.gd, …
scripts/ui/        menu.gd, hud.gd, pause_menu.gd, settings_ui.gd, gauge.gd, minimap.gd, ui_kit.gd
scripts/util/      mesh_kit.gd (prozedurale Meshes), tex_kit.gd (Shader & Texturen)
assets/cars/       r34.glb, mustang.glb, m3gt3.glb (+ Maße als JSON), CREDITS.md
assets/audio/      R34-Motor- und Turbo-Samples (aus tools/make_r34_audio.py)
assets/env/        garage.glb (Hauptmenü-Halle, aus tools/convert_garage.py) + garage.json (Mitte der Halle)
tools/             convert_cars.py (Blend → GLB), preview_car.py, make_r34_audio.py (Aufnahmen → Samples),
                   convert_garage.py (3ds-Max-Szene → GLB)
tests/             Skript-, Audio-, Fahr-, Kamera- und Screenshot-Tests (scene_shots, ui_shots, garage_shots)
```

## Credits

Die Automodelle stammen von [Blend Swap](https://www.blendswap.com). Details stehen in `assets/cars/CREDITS.md`:

- Nissan Skyline R34 GT-R – Blend Swap #92438, **CC-BY 3.0**
- Ford Mustang GT – Blend Swap #92324, CC0
- BMW M3 GT3 – „Bmw M3 Gt3“ von Neubi, Blend Swap #19869, CC0

Die Modelle wurden mit `tools/convert_cars.py` (Blender 4.2) in GLB-Dateien umgewandelt. Die Vorschau-Renderings
erzeugt `tools/preview_car.py`.

R34-Sound: Die Aufnahmen „R34 Skyline Dyno Test (Compilation)“ (Vollgas), „Top Speed Autosport HKS Hi-Power
Exhaust Nissan GTR R34“ (Schiebebetrieb, Leerlauf) und „Nissan Skyline GTR R34 Turbo Sound“ (Turbo, Blow-off) wurden
vom Projektinhaber bereitgestellt und mit `tools/make_r34_audio.py` geschnitten und aufbereitet. Bevor du das Spiel weitergibst, kläre die Rechte an diesen
Aufnahmen – ohne sie nutzt der R34 automatisch den synthetischen Motorsound.

Garage im Hauptmenü: Die 3ds-Max-Szene „Garage.max“ samt Texturen wurde vom Projektinhaber bereitgestellt und mit
`tools/convert_garage.py` umgewandelt (Parser: Blender-Add-on „Import Autodesk MAX“, GPL, wird nur zum Konvertieren
benutzt und nicht mitgeliefert). Die Halle und die Poster darin stammen vermutlich aus einem anderen Spiel – kläre auch
hier die Rechte, bevor du das Spiel weitergibst. Fehlt `assets/env/garage.glb`, zeigt das Menü das alte Studio.
