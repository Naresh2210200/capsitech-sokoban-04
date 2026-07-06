shader_type canvas_item;

uniform vec2 scroll_speed = vec2(0.03, 0.015);

void fragment() {
	vec2 uv = fract(UV + TIME * scroll_speed);
	COLOR = texture(TEXTURE, uv);
}