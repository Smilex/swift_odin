package main

import "base:runtime"
import MTL "vendor:darwin/Metal"
import NS  "core:sys/darwin/Foundation"
import "base:intrinsics"

game_context :: struct {
    library: ^MTL.Library,
    pso: ^MTL.RenderPipelineState,

    pos_buf: ^MTL.Buffer,
    col_buf: ^MTL.Buffer,
}

g_ctx: ^game_context

build_shaders :: proc(device: ^MTL.Device) -> (library: ^MTL.Library, pso: ^MTL.RenderPipelineState, err: ^NS.Error) {
	shader_src := `
	#include <metal_stdlib>
	using namespace metal;

	struct v2f {
		float4 position [[position]];
		half3 color;
	};

	v2f vertex vertex_main(uint vertex_id                        [[vertex_id]],
	                       device const packed_float3* positions [[buffer(0)]],
	                       device const packed_float3* colors    [[buffer(1)]]) {
		v2f o;
		o.position = float4(positions[vertex_id], 1.0);
		o.color = half3(colors[vertex_id]);
		return o;
	}

	half4 fragment fragment_main(v2f in [[stage_in]]) {
		return half4(in.color, 1.0);
	}
	`
	shader_src_str := NS.String.alloc()->initWithOdinString(shader_src)
	defer shader_src_str->release()

	library = device->newLibraryWithSource(shader_src_str, nil) or_return

	vertex_function   := library->newFunctionWithName(NS.AT("vertex_main"))
	fragment_function := library->newFunctionWithName(NS.AT("fragment_main"))
	defer vertex_function->release()
	defer fragment_function->release()

	desc := MTL.RenderPipelineDescriptor.alloc()->init()
	defer desc->release()

	desc->setVertexFunction(vertex_function)
	desc->setFragmentFunction(fragment_function)
	desc->colorAttachments()->object(0)->setPixelFormat(.BGRA8Unorm_sRGB)

	pso = device->newRenderPipelineStateWithDescriptor(desc) or_return
	return
}

build_buffers :: proc(device: ^MTL.Device) -> (vertex_positions_buffer, vertex_colors_buffer: ^MTL.Buffer) {
	NUM_VERTICES :: 3
	positions := [NUM_VERTICES][3]f32{
		{-0.8,  0.8, 0.0},
		{ 0.0, -0.8, 0.0},
		{+0.8,  0.8, 0.0},
	}
	colors := [NUM_VERTICES][3]f32{
		{1.0, 0.3, 0.2},
		{0.8, 1.0, 0.0},
		{0.8, 0.0, 1.0},
	}

	vertex_positions_buffer = device->newBufferWithSlice(positions[:], MTL.ResourceStorageModeShared)
	vertex_colors_buffer    = device->newBufferWithSlice(colors[:],    MTL.ResourceStorageModeShared)
	return
}

@export
game_init :: proc "cdecl" (device: ^MTL.Device) {
    context = runtime.default_context()
    g_ctx = new(game_context)

    err: ^NS.Error
    g_ctx.library, g_ctx.pso, err = build_shaders(device)
    g_ctx.pos_buf, g_ctx.col_buf = build_buffers(device)
}

@export
game_update_and_render :: proc "cdecl" (drawable: ^MTL.Drawable, command_buffer: ^MTL.CommandBuffer, render_pass_desc: ^MTL.RenderPassDescriptor) {
    enc := command_buffer->renderCommandEncoderWithDescriptor(render_pass_desc)
    if enc != nil {
        enc->setRenderPipelineState(g_ctx.pso)
		enc->setVertexBuffer(g_ctx.pos_buf, 0, 0)
		enc->setVertexBuffer(g_ctx.col_buf,    0, 1)
		enc->drawPrimitives(.Triangle, 0, 3)

        enc->endEncoding()
    }
}
