shader_type canvas_item;
// Простейший fisheye-шейдер для имитации объектива GoPro/FPV.
// Вешается на TextureRect с TextureScreen (CanvasLayer над камерой).

uniform float strength : hint_range(0.0, 1.0) = 0.35; // Сила искажения
uniform vec2 center = vec2(0.5, 0.5);                 // Центр искажения

void fragment() {
	// Нормализованные координаты относительно центра экрана
	vec2 uv = UV - center;
	float r = length(uv);
	// Баррельная дисторсия: чем ближе к краю, тем сильнее "выпучивание"
	float theta = atan(r * 2.0);
	float distortion = 1.0 + strength * (theta / max(r, 0.0001) - 1.0);
	vec2 distorted = uv * distortion + center;
	// За пределами экрана — чёрный (виньетка краёв)
	if (distorted.x < 0.0 || distorted.x > 1.0 || distorted.y < 0.0 || distorted.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		COLOR = texture(TEXTURE, distorted);
	}
}
