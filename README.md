# Midnight Drift

Ein Drift-Racing-Spiel mit Godot 4.3. Autos, Strecken, Bäume, Häuser, Himmel, Texturen und Sounds
werden beim Start **prozedural im Code erzeugt**. Das Spiel braucht keine fremden Assets.

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
| Grafik | Forward+-Renderer, dynamische Schatten (Sonne mit 4 Kaskaden, Scheinwerfer werfen Schatten), SSAO, SSR, Glow, ACES-Tonemapping, Nebel |
| Skybox | eigener Sky-Shader mit Wolken, Sonne, Mond und Sternen; 4 Tageszeiten (Mittag, Sonnenuntergang, Nacht, Morgennebel) |
| Strecken | **Kurohana Ridge** (fließende Waldstrecke mit ~1,9 km) und **Harbor Drift Yard** (breiter Hafenkurs mit ~1,3 km und engen Kehren). Beide haben Curbs, Leitplanken bzw. Betonwände, ein Startportal mit Startampel und Straßenlaternen |
| Bäume | prozedurale Laub- und Nadelbäume: rekursive, gebogene und verjüngte Äste, tausende Blattkarten mit generierter Blatt- bzw. Nadeltextur, Rinden-Normalmap, Wind im Shader, 2 LOD-Stufen |
| Häuser | japanische Wohnhäuser, Laden mit Getränkeautomaten, Scheune, Büro, Lagerhallen, Container, Kräne, Schiffe, Skyline. Nachts leuchten die Fenster |
| Standardauto | **Skyline GT-R R34 (Verschnitt)** in **Midnight Purple II**: Chamäleon-Lack (Farbwechsel je nach Blickwinkel, Metallic-Flakes, Klarlack), 4 runde Rückleuchten, Heckflügel |
| Weitere Autos | Silvia S15, Trueno AE86, Supra A80 (alle als Verschnitt). 8 Lackierungen plus eigene Farbe |
| Licht | Scheinwerfer mit dynamischen Spotlights (L), Bremslicht, Rückfahrlicht, Unterbodenbeleuchtung. Bei Dämmerung und Nacht schaltet sich das Licht automatisch ein |
| Physik | eigenes Raycast-Fahrwerk: Federung, Dämpfer, Stabis, Reifenmodell mit Schräglaufwinkel und Reibungskreis. Radschlupf und Handbremse lassen das Heck ausbrechen. Dazu eine Konter-Lenkhilfe (einstellbar) |
| Getriebe | alle Autos starten mit **Automatik**. **Manuell** lässt sich jederzeit in der Garage oder beim Fahren mit **M** umschalten |
| Sound | in Echtzeit synthetisiert: Motor, Turbo-Pfeifen, **Blow-off beim Schalten** (S15 mit Flattern), Fehlzündungen, Reifenquietschen, Wind, Aufprall |
| Effekte | Reifenrauch, Staub auf Gras bzw. Beton, Bremsspuren, Flammen aus dem Auspuff |
| Driftpunkte | Winkel × Geschwindigkeit × Zeit, Combo-Multiplikator (bis x6), Bonus für Richtungswechsel und für Driften nah an der Wand. Wandkontakt oder Offroad kostet die Combo |
| Leaderboard | lokal pro Strecke: Driftpunkte, bester Einzeldrift, beste Runde, Rennzeit (Top 10). Im Rennen zeigt **Tab** die Live-Rangliste |
| Modi | Freies Driften, Rennen, Drift-Battle. Einstellbar sind 1–20 Runden, Tageszeit und Strecke |
| Online | Lobbys mit **Self-Hosting durch den Lobby-Ersteller** (ENet, UDP-Port 24570). Automatische Portfreigabe per UPnP, LAN-Lobby-Suche, Chat und Bereit-Status. Der Host stellt Strecke, Modus, Runden, Tageszeit und Kollisionen ein. Ergebnisse werden am Ende synchronisiert |

## Steuerung

| Taste | Aktion |
|---|---|
| W / ↑ / RT | Gas |
| S / ↓ / LT | Bremse / Rückwärts |
| A, D / ←, → / Stick | Lenken |
| Leertaste / (A) | Handbremse |
| E oder Shift / RB | Hochschalten (manuell) |
| Q oder Strg / LB | Runterschalten (manuell) |
| M | Automatik ⇄ Manuell |
| C / (Y) | Kamera wechseln (Verfolger, weit, Motorhaube, Stoßstange, Dach) |
| **V** / R-Stick-Klick | **Kamera-Lock lösen**: freie Orbit-Kamera mit Maus bzw. rechtem Stick, Mausrad zoomt |
| Rechte Maustaste halten | kurz umsehen |
| B / (X) | nach hinten schauen |
| R / Back | Auto auf die Strecke zurücksetzen |
| L | Licht an/aus |
| Tab | Leaderboard / Spielerliste |
| F1 | Hilfe ein/aus |
| Esc / Start | Pause |

## Online spielen

- **Host:** *Online-Modus → Lobby erstellen.* Dein PC ist der Server. Im LAN finden dich Mitspieler
  automatisch. Über das Internet klappt es, wenn UPnP den Port öffnen kann (der Status steht in der
  Lobby). Sonst gibst du im Router **UDP-Port 24570** frei (der Port ist einstellbar). Deinen
  Mitspielern gibst du deine öffentliche IP.
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
scripts/world/     world.gd (Rennablauf), track.gd, scenery.gd, tree_factory.gd, environment_builder.gd, …
scripts/ui/        menu.gd, hud.gd, pause_menu.gd, gauge.gd, minimap.gd, ui_kit.gd
scripts/util/      mesh_kit.gd (prozedurale Meshes), tex_kit.gd (Shader & Texturen)
```

Die Autos sind eigenständige Nachbildungen im Stil der bekannten JDM-Klassiker ("Verschnitt"). Es
werden keine Original-Modelle oder Markenlogos verwendet.
