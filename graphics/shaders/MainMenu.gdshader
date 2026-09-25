shader_type canvas_item;

uniform vec2 hole_center = vec2(0.8, 0.7); // normalized 0-1, relative to the rect
uniform float hole_radius = 0.15;           // normalized 0-1
uniform float edge_softness = 0.01;
uniform vec2 rect_size = vec2(1.0);        // set from script to avoid ellipse on non-square rects

void fragment() {
    vec2 uv = (UV - hole_center) * rect_size;
    float dist = length(uv);
    float radius_px = hole_radius * min(rect_size.x, rect_size.y);
    float mask = smoothstep(radius_px, radius_px + edge_softness * rect_size.x, dist);
    COLOR.a *= mask; // 0 inside the hole, 1 outside, smooth blend at the edge
}