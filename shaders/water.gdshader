shader_type canvas_item;
// Блеск на воде поверх карты: текстура — маска реки (белое = вода). Пиксельные искры и бегущие блики.
uniform vec2 world_size = vec2(2400.0, 1600.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float m = texture(TEXTURE, UV).r;
	vec2 px = floor(UV * world_size);
	float t = floor(TIME * 5.0);
	float spark = step(0.9972, hash(px + vec2(t * 7.0, t * 3.0)));
	float band = step(0.985, sin(px.y * 0.21 - TIME * 2.2 + sin(px.x * 0.09 + TIME) * 2.0));
	float a = max(spark * 0.9, band * 0.35) * m;
	COLOR = vec4(0.78, 0.9, 0.98, a);
}
