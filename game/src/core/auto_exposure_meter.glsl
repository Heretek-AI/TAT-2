#[compute]
#version 450
// TAT-2 P4.1b AEM meter — log-luminance reduction.
//
// One workgroup per 32x32 screen tile; 8x8 threads cover the tile (each
// thread walks its 4x4 strided sub-grid). Each group writes the AVERAGE of
// log2(luminance * 100) over its tile into a float storage buffer. The CPU
// (AutoExposureMeter.read_ev100) averages the group values, which is exactly
// what `AutoExposureMeter.reduce_log_luminance()` does for the headless
// synthetic harness. No atomics, no per-pixel readback.
//
// EV100 convention matches UE's AEM_Basic: log2(luminance * 100 / 1.0), i.e.
// 0.18 grey -> log2(18) = 4.1699 EV100.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D scene_color;

layout(set = 0, binding = 1, std430) restrict writeonly buffer GroupAvgBuffer {
	float group_avg[];
} out_buf;

layout(push_constant, std430) uniform Params {
	ivec2 size;
	uint groups_x;
	uint groups_y;
} params;

const int TILE = 32;
const int LOCAL_X = 8;
const int LOCAL_Y = 8;
const float EPS = 1e-6;

shared float partial[LOCAL_X * LOCAL_Y];
shared uint counts[LOCAL_X * LOCAL_Y];

void main() {
	uvec2 gid = gl_WorkGroupID.xy;
	ivec2 base = ivec2(gid) * TILE;
	ivec2 limit = min(ivec2(params.size), base + ivec2(TILE));

	float sum = 0.0;
	uint count = 0u;
	for (int y = base.y + int(gl_LocalInvocationID.y); y < limit.y; y += LOCAL_Y) {
		for (int x = base.x + int(gl_LocalInvocationID.x); x < limit.x; x += LOCAL_X) {
			vec3 c = texelFetch(scene_color, ivec2(x, y), 0).rgb;
			float lum = max(dot(c, vec3(0.2126, 0.7152, 0.0722)), EPS);
			sum += log2(lum * 100.0);
			count++;
		}
	}

	uint lid = gl_LocalInvocationID.y * LOCAL_X + gl_LocalInvocationID.x;
	partial[lid] = sum;
	counts[lid] = count;
	barrier();

	if (lid == 0u) {
		float total = 0.0;
		uint total_count = 0u;
		for (int i = 0; i < LOCAL_X * LOCAL_Y; i++) {
			total += partial[i];
			total_count += counts[i];
		}
		uint group = gid.y * params.groups_x + gid.x;
		out_buf.group_avg[group] = total / float(max(total_count, 1u));
	}
}
