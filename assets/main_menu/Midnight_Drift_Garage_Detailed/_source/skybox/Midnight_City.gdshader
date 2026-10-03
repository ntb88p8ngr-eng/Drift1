shader_type sky;
uniform sampler2D panorama : source_color, filter_linear, repeat_enable;
uniform float exposure : hint_range(0.0, 4.0) = 1.0;
uniform float horizontal_offset : hint_range(0.0, 1.0) = 0.37;
void sky() { COLOR = texture(panorama, vec2(fract(SKY_COORDS.x + horizontal_offset), SKY_COORDS.y)).rgb * exposure; }
