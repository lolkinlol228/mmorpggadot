shader_type canvas_item;
// Ветер: верх спрайта (дерево, куст) покачивается, низ стоит на месте. Сдвиг шагами в целый пиксель.
uniform float strength = 1.6;

void vertex() {
	float h = 1.0 - UV.y;
	float phase = MODEL_MATRIX[3].x * 0.043 + MODEL_MATRIX[3].y * 0.021;
	float s = sin(TIME * 1.25 + phase) + 0.35 * sin(TIME * 2.9 + phase * 1.7);
	VERTEX.x += floor(s * strength * h * h + 0.5);
}
