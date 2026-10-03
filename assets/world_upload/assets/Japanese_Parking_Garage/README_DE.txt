JAPANISCHES PARKHAUS – SAKURA / 桜 駐車場

Dateien
parking_garage.blend – bearbeitbare Blender-Szene, Texturen eingebettet
parking_garage.glb – Austauschformat mit eingebetteten Materialien und Texturen
parking_garage.obj + .mtl – alternative Geometrie mit externen PNG-Texturen
textures/ – 40 PBR-Sets mit Basisfarbe, Rauheit und Normalmaps
preview_*.png – Außen-, Tiefgaragen- und Schnittansicht
scene_info.json – Abmessungen und Geometrie-Statistik
project.godot + Main.tscn – direkt startbares Godot-4-Projekt
disable_floor_marking_shadows.gd – deaktiviert Schatten der Bodenmarkierungen

Aufbau
B2: -6,8 m, B1: -3,4 m, G: 0 m, L1: +3,4 m, L2: +6,8 m
157 nummerierte Stellplätze (Bereich 001–160, drei Plätze für die Zufahrt frei);
8 grün markierte E-Ladeplätze.
Hauptgebäude 44 × 28 m; seitlicher Rampenbereich 6 m breit.
Vier wechselnde Rampen verbinden die fünf Ebenen, 26 m Fahrbahnlänge
je Ebene, ca. 13,1 % Steigung. Oberste Ebene als offenes Parkdeck.
Japanische Beschilderung, Linksverkehr, Kassenautomaten, Getränkeautomaten,
Schranken, Pförtnerkabine, Treppen und Aufzugstüren, Lüftungskanäle,
Ventilatoren, Sprinklerleitungen, Brandschutzschränke und Leuchten.
Alle 3.615 Mesh-Objekte verwenden eines von 40 unterschiedlichen PBR-Materialsets.
Die fünf Parkebenen, Wände und Säulen haben jeweils eigene Oberflächen.
Weitere Sets decken Rampen, Asphalt, Pflaster, Fliesen, Beton, Metall, Glas,
Gummi, Lack, Warnstreifen, Automaten und Leuchten ab. Insgesamt sind
120 Texturkarten enthalten.

Import
Blender: .blend öffnen, oder .glb importieren.
Godot 4: Paket entpacken und project.godot öffnen. Main.tscn lädt die GLB
und deaktiviert den Schattenwurf aller Bodenlinien, Pfeile, Nummern und Texte.
Unity: .glb mit einem glTF-Importer importieren; alternativ OBJ und MTL
zusammen mit den PNG-Dateien verwenden.
Maßstab: Meter. Die Blender-Szene verwendet Z nach oben; GLB konvertiert
beim Export die Achsen. Ebenen sind in benannten Collections organisiert.

Hinweise
Modell für Visualisierung und Spiele. Aufzug, Schranken und Automaten sind
statische Modelle; Steuerung, Kollisionen und Fahrphysik sind nicht enthalten.
Blender enthält Kameras und Beleuchtung; GLB/OBJ enthalten die sichtbaren
Leuchten als Geometrie, jedoch keine Laufzeit-Lichtquellen.
Die Schnittansicht ist nur eine Vorschau; das exportierte Modell ist vollständig.
Bodenmarkierungen sind nur ca. 1 mm über dem Belag und werfen keine Schatten.
Das Modell enthält keine Fahrzeuge und keine Menschen.

Schrift: Noto Sans JP, SIL Open Font License 1.1 (siehe FONT_LICENSE.txt).
