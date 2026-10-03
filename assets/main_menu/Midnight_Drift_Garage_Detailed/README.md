# Midnight Drift — Dark Automotive Workshop

A crowded red-and-black workshop reconstructed from the garage reference, with no car. The round neon platform, open rear shutter, banners and industrial shell remain the centre of the scene. This revision uses darker surface textures and an asymmetric arrangement of service equipment and loose parts. Scale and hidden surfaces are inferred from the image.

## Revision details

- Hollow radial car tyres with broad tread surfaces, rounded shoulders, separated tread blocks, bead openings and moulded size markings: 205/55 R16, 225/45 R17, 235/40 R18 and 275/35 R19. Alloy wheels include barrels, cast spokes, hubs, lug nuts and air valves. The stacks differ in height and size and are slightly offset.
- A conventional floorplate two-post lift in a separate service bay. Approximately 3.35 m wide and 3.13 m high, with anchored bases, C-section columns, slide rails, carriages, lock ladders, hydraulic rams, telescopic swing arms, four threaded rubber support pads, power unit and controls. The low cable cover crosses the floor. Generic proportions informed by the floorplate lift drawing in https://www.bendpak.com/media/wysiwyg/Manuals/XPR-9Series-5900371-RevD4-January2024.pdf; this is an unbranded visual model.
- A spare inline engine on a rotating stand in the rear-left corner: block casting ribs, cylinder head, valve cover, oil sump/filter, plugs and ignition wires, intake plenum, throttle bore, four-into-one exhaust header, alternator, pulleys and dipstick.
- Car service projects: brake rotors/calipers/pads, two different coilovers, manual gearbox, intercooler, spare turbo, exhaust section, torque wrench, impact gun and oil drain pan.
- Visible differences in spanner length and jaw size, driver length and grip thickness, and socket diameter/depth.
- Angled trolleys, open drawers, irregular shelf gaps, varied box sizes and orientations, uneven bottles, scattered fasteners, used rags and an uncoiled air hose. Structural columns, shelving and lift guides remain mechanically aligned.
- Charcoal concrete, worn dark crimson paint, dark steel, black rubber and dimmer wood/cardboard surfaces. Red platform neon and practical work lights provide the main accents.
- A new night city skybox at street level, with pavement, curbs and nearby warehouse fronts below distant towers.

## Import files

**Midnight_Drift_Garage.glb** is the complete scene, with separate named component nodes, assembly parents, embedded PBR textures, punctual lights, reference camera and platform animation. **Neon_Turntable.glb** contains the platform alone at the origin. **Midnight_Drift_Garage.obj / .mtl** provides static geometry as separate OBJ objects; keep the textures directory beside it.

Run **Import_into_Blender.py** in Blender's Scripting workspace to import into a new scene, make repeated mesh data independent and save a .blend file locally. A prebuilt .blend is not supplied. **Garage_Preview.png** and **Service_Bay_Detail.png** are raster renders of the actual authored geometry. Their lighting and reflections are approximate; appearance depends on the target renderer.

**Object_Inventory.csv**, **Assembly_Inventory.json**, **Scene_Manifest.json** and **Asset_Validation.json** record object membership, dimensions, materials, polygon counts and structural checks.

Every fastener, tread block, drawer, handle, tool component, bottle, carton detail and cable segment is independently transformed. Repeated components share immutable mesh data to keep the GLB smaller. Make meshes single-user when editing individual vertices, or use the included Blender script. No scene-wide mesh merge is used.

## Scale and platform

Approximate interior: 13.6 × 12.8 × 4.96 metres. Platform diameter: approximately 7.5 metres; deck height: approximately 0.465 metres. GLB is Y-up; OBJ source is Z-up. The turntable pivot is at the scene origin.

**Turntable_360_20s** makes one full revolution in 20 seconds. Enable looping in your engine. Parent the vehicle to **Turntable_ROTATE** and position it on the deck. The static pedestal, segmented outer neon and front nameplate remain fixed; the deck, skirt, fasteners and trim rotate together.

## Materials and background

PBR surface maps are primarily 1024 or 2048 pixels. Packed ORM channels: R = occlusion, G = roughness, B = metallic. Normal maps follow glTF conventions. Enable glow and configure environment lighting/reflections in the target engine.

The panorama and six cube faces are in **skybox/**, with engine import notes and a Godot sky shader. Assign the panorama separately as your environment background; it is not embedded in the GLB. Native panorama resolution: 1774 × 887, LDR RGB. Six 1024 × 1024 cube faces are technical reprojections and do not add native image detail. The city is now viewed from approximately 1.4 metres above street level.

Poster and banner meshes select the visible artwork from the original screenshot through UVs. The original atlas bitmap is unchanged; no car or menu region is mapped to scene geometry.

## Rebuild and game use

Requires Python 3.10+, numpy, Pillow and scipy. Run **source/build_detailed.py** to regenerate exports under **output/Midnight_Drift_Garage_Detailed/**. The included source/assets atlas and skybox files make the build independent of a separate screenshot download. Run **source/render_detailed.py** for the garage render, or add **--view service** for the detail view. Run **source/validate_detailed.py** for structural checks.

The scene prioritizes editing. Batch or instance components appropriately for a game build after editing. Collisions and baked lightmaps are not included.
