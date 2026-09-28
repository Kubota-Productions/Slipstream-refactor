shader_type spatial;
render_mode cull_front, depth_draw_always, unshaded;

// ============================================================
// OBJECT HIGHLIGHT OUTLINE
//
// Renders an inflated, inside-out duplicate of the mesh (cull_front
// keeps only the back faces) so a thin rim of highlight_color pokes
// out around the object's silhouette from any angle.
//
// SETUP:
// 1. Create a new ShaderMaterial using this shader.
// 2. On that ShaderMaterial resource, tick "Local To Scene" (bottom
//    of the Inspector) -- without this, every instance of the object
//    shares one Material resource, so highlighting one highlights
//    all of them at once.
// 3. Assign it as the object's existing material's NEXT PASS
//    (Material -> Next Pass in the Inspector), NOT as the main
//    material -- this keeps the object's own texture/lighting intact
//    and only adds this outline on top.
// 4. Add the object (or its root body) to the "interactable" group
//    (or whatever group InteractionHighlightController.target_group
//    is set to).
//
// highlight_amount is driven every frame by
// InteractionHighlightController -- 0 = invisible, 1 = full outline.
// It's exposed as a uniform (not a script-only constant) so you can
// also scrub it manually in the Inspector while testing.
// ============================================================

uniform vec4 highlight_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// How far the outline extends beyond the mesh's own surface, in the
// mesh's local units. Larger objects usually want a slightly larger
// value to read clearly at a distance.
uniform float outline_width : hint_range(0.0, 1) = 0.015;

// 0 = fully hidden, 1 = fully visible. Set from script.
uniform float highlight_amount : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	// VERTEX/NORMAL here are in local (model) space. Pushing the
	// vertex outward along its own normal inflates the whole mesh
	// slightly -- combined with cull_front (only back faces survive
	// rasterization), the inflated back faces poke out past the real
	// front-facing surface's silhouette, reading as a rim outline.
	//
	// Scaling by highlight_amount as well as outline_width means an
	// amount of 0 collapses the outline back down to zero thickness
	// (sitting exactly inside the original mesh, so nothing shows)
	// instead of just becoming transparent while still geometrically
	// poking out -- avoids a faint edge lingering at glancing angles
	// when the highlight is supposed to be fully off.
	VERTEX += NORMAL * outline_width * highlight_amount;
}

void fragment() {
	ALBEDO = highlight_color.rgb;
	ALPHA = highlight_color.a * highlight_amount;
}
