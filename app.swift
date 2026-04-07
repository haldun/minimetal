import Cocoa
import Metal
import MetalKit

// Create the window
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = NSWindow(
    contentRect: .init(x: 0, y: 0, width: 640, height: 480),
    styleMask: [.titled, .closable, .resizable],
    backing: .buffered,
    defer: false
)
window.title = "Metal Demo"
window.makeKeyAndOrderFront(nil)

// Make cmd+q to terminate the app
let menu = NSMenu()
let appMenu = NSMenu()
appMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose), keyEquivalent: "w")
appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate), keyEquivalent: "q")
let appMenuItem = NSMenuItem()
appMenuItem.submenu = appMenu
menu.addItem(appMenuItem)
app.mainMenu = menu

// Terminate the app when the window is closed
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }
}
let delegate = AppDelegate()
app.delegate = delegate

// Get the device
guard let device = MTLCreateSystemDefaultDevice() else { fatalError("No GPU") }

// Shaders
let shaderSource = #"""
#include <metal_stdlib>
using namespace metal;

vertex float4 vertex_main(const device float2* positions [[buffer(0)]],
                          uint id [[vertex_id]]) {
    return float4(positions[id], 0.0, 1.0);
}

fragment float4 fragment_main(float4 pos [[position]],
                              constant float &time [[buffer(0)]],
                              constant float2 &res [[buffer(1)]]) {
    float2 uv = pos.xy / res.y * 6.0;
    float2 i_uv = floor(uv);
    float2 f_uv = fract(uv);

    float minDist = 1.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 neighbor = float2(float(x), float(y));
            float2 p = i_uv + neighbor;
            float2 rnd = fract(sin(float2(dot(p, float2(127.1, 311.7)),
                                          dot(p, float2(269.5, 183.3)))) * 43758.5453);
            float2 point = neighbor + 0.5 + 0.5 * sin(time + 6.2831 * rnd);
            float d = length(point - f_uv);
            minDist = min(minDist, d);
        }
    }
    float3 col = 0.5 + 0.5 * cos(6.2831 * (minDist + float3(0.2, 0.5, 0.8)));
    col *= smoothstep(0.02, 0.05, minDist);
    return float4(col, 1.0);
}
"""#

// Compile the shader
let library = try! device.makeLibrary(source: shaderSource, options: nil)
guard let vertexFunc = library.makeFunction(name: "vertex_main") else {
    fatalError("Failed to make function `vertex_main`")
}
guard let fragmentFunc = library.makeFunction(name: "fragment_main") else {
    fatalError("Failed to make function `fragment_main`")
}
guard let commandQueue = device.makeCommandQueue() else {
    fatalError("Failed to create command queue")
}
let pipelineDescriptor = MTLRenderPipelineDescriptor()
pipelineDescriptor.vertexFunction = vertexFunc
pipelineDescriptor.fragmentFunction = fragmentFunc
pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
let pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)

// Renderer of the MTKView
class Renderer: NSObject, MTKViewDelegate {
    // Fullscreen triangle (oversized to cover the whole viewport)
    let vertices: [Float] = [
        -1.0, -1.0,
         3.0, -1.0,
        -1.0,  3.0,
    ]

    let commandQueue: MTLCommandQueue
    let pipelineState: MTLRenderPipelineState
    let vertexBuffer: MTLBuffer
    let startTime = CFAbsoluteTimeGetCurrent()

    init(commandQueue: MTLCommandQueue, pipelineState: MTLRenderPipelineState) {
        self.commandQueue = commandQueue
        self.pipelineState = pipelineState
        guard let vertexBuffer = commandQueue.device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.size,
            options: []
        ) else { fatalError("Failed to create vertex buffer") }
        self.vertexBuffer = vertexBuffer
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable, let descriptor = view.currentRenderPassDescriptor else { return }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            fatalError("Failed to create command buffer")
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            fatalError("Failed to create render command encoder")
        }
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        var time = Float(CFAbsoluteTimeGetCurrent() - startTime)
        encoder.setFragmentBytes(&time, length: MemoryLayout<Float>.size, index: 0)
        var resolution = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        encoder.setFragmentBytes(&resolution, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
let renderer = Renderer(commandQueue: commandQueue, pipelineState: pipelineState)

// Create MTKView
let view = MTKView(frame: window.contentView!.bounds, device: device)
view.clearColor = .init(red: 0.1, green: 0.1, blue: 0.2, alpha: 1.0)
view.delegate = renderer
window.contentView = view

// Kick off the run loop
app.run()
