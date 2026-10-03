# Midnight City Skybox — corrected panorama edition

`Midnight_City_Panorama.png` is a true 2:1 equirectangular panorama (1774 × 887). It keeps the viewpoint at wet street level and is not cropped, scaled, or pre-zoomed.

For Godot 4, copy this folder into the project, then assign the included `Midnight_City_Sky.tres` to an Environment or use the PNG directly in a `PanoramaSkyMaterial`.

Important: the panorama slot must receive `Midnight_City_Panorama.png`. The earlier cubemap-cross and custom sky shader are deliberately omitted because loading a cross image as a panorama creates the stretched/zoomed appearance.

