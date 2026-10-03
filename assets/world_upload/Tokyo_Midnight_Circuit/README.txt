TOKYO MIDNIGHT CIRCUIT — GODOT 4 PROJECT

Open project.godot in Godot 4.x and press F6/F5 (or click Run Project).
The district is generated from scripts/map_generator.gd when the scene runs.
The project includes tileable image-based albedo, normal and roughness maps in textures/.

Scene scale: 1 Godot unit = 1 metre. The playable district spans roughly 700 x 700 m.
TokyoDistrict.tscn is the main scene. The generated scene contains:
- Dense Tokyo-inspired shop, office and apartment blocks with lit windows and rooftop detail
- Textured asphalt, concrete, brick, metal, glass, sidewalk, roof and car paint materials
- A ground-level multilane expressway and an independent elevated closed race circuit
- Open local streets, marked parking lots and car-meet parking bays
- Street lamps, traffic signals, barriers, road markings, overhead signs and Japanese-inspired neon
- A high overview camera with WASD flight controls; hold right mouse and move to look, scroll to adjust speed

Geometry is generated in Godot at runtime. All texture maps and the optional texture generator are included in this project.
