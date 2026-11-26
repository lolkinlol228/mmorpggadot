shader_type canvas_item;
// Мягкое затемнение краёв экрана + цвет ночи по краям.
uniform float strength = 0.45;
uniform vec4 tint : source_color = vec4(0.05, 0.04, 0.10, 1.0);

void fragment() {
	vec2 d = UV - vec2(0.5);
	float v = smoothstep(0.32, 0.78, length(d * vec2(1.0, 1.25)));
	COLOR = vec4(tint.rgb, v * strength);
}
