shader_type canvas_item;

<<<<<<< HEAD
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
=======
uniform sampler2D mask_tex : source_color, filter_nearest;
uniform sampler2D pattern_tex : source_color, repeat_enable, filter_nearest;

uniform vec2 tile_count = vec2(8.0, 8.0);
uniform vec2 scroll_speed = vec2(0.10, 0.05);

// UI-facing settings.
uniform float projection_angle_degrees = 50.0;
uniform float copy_spacing_pixels = 12.0;

// Color progression: each copy moves from user_color toward black.
uniform vec4 front_color : source_color = vec4(1.0);
uniform vec4 user_color : source_color = vec4(0.25, 0.65, 1.0, 1.0);

vec4 over(vec4 back, vec4 front) {
    // Standard alpha compositing: front is visually above back.
    vec3 rgb = front.rgb * front.a + back.rgb * (1.0 - front.a);
    float alpha = front.a + back.a * (1.0 - front.a);
    return vec4(rgb, alpha);
}

vec4 make_layer(vec2 layer_uv, vec4 layer_color) {
    vec2 scrolling_uv = fract(layer_uv * tile_count + scroll_speed * TIME);
    vec4 texel = texture(pattern_tex, scrolling_uv);

    return vec4(texel.rgb * layer_color.rgb, texel.a * layer_color.a);
}

void fragment() {
    float mask_alpha = texture(mask_tex, UV).a;

    // Convert degrees from the Inspector to radians for cos/sin.
    float angle_rad = radians(projection_angle_degrees);
    vec2 direction = vec2(cos(angle_rad), sin(angle_rad));

    // Convert pixel spacing into UV spacing, so it stays visually in pixels.
    vec2 pixel_to_uv = 1.0 / TEXTURE_PIXEL_SIZE;
    vec2 one_copy_offset = direction * copy_spacing_pixels * pixel_to_uv;

    // A sample at UV - offset is DRAWN at UV + offset.
    vec4 back_copy = make_layer(UV - one_copy_offset * 2.0, mix(user_color, vec4(0.0), 0.65));
    vec4 middle_copy = make_layer(UV - one_copy_offset, mix(user_color, vec4(0.0), 0.32));
    vec4 front_layer = make_layer(UV, front_color);

    // Back-to-front compositing establishes layering.
    vec4 result = over(back_copy, middle_copy);
    result = over(result, front_layer);

    // Apply the hole last, to every copy together.
    result.a *= mask_alpha;

    COLOR = result;
>>>>>>> Experimental_frontend
