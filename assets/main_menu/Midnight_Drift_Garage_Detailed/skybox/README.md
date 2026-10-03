# Midnight City — Street Level

Night industrial street viewed from approximately 1.4 metres above the pavement. Nearby warehouse fronts, street curbs and asphalt replace the previous elevated city view. No cars or people.

Use Midnight_City_Panorama.png as an equirectangular environment background. Native resolution: 1774 × 887, LDR RGB. In Godot, assign it to a PanoramaSkyMaterial under a WorldEnvironment Sky. The included shader exposes environment exposure and horizontal offset controls. It defaults to an offset of 0.37 turns (133.2 degrees) to face the street. Apply the same panorama rotation in other engines if desired.

Six 1024 × 1024 cube faces and a cross-layout preview are included. Coordinate convention: +Y up, +Z front, +X right. Face dimensions do not add native detail. The panorama is separate from the GLB; assign it in your target engine. The cube faces already apply the 0.37-turn street-facing rotation. The original panorama remains unchanged.

The authored scene's exterior apron is at floor level. Keep the panorama camera stationary or use it as a distant background; nearby road geometry in a skybox does not provide positional parallax.
