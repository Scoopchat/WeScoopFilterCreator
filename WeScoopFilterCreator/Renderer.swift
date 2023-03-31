//
//  Renderer.swift
//  WeScoopFilterCreator
//
//  Created by Dorian on 29.03.2023.
//

import Foundation
import Metal
import MetalKit
import ARKit

/*protocol RenderDestinationProvider {
    var currentRenderPassDescriptor: MTLRenderPassDescriptor? { get }
    var currentDrawable: CAMetalDrawable? { get }
    var colorPixelFormat: MTLPixelFormat { get set }
    var depthStencilPixelFormat: MTLPixelFormat { get set }
    var sampleCount: Int { get set }
}*/

// The max number of command buffers in flight
let kMaxBuffersInFlight: Int = 3

// The max number anchors our uniform buffer will hold
let kMaxAnchorInstanceCount: Int = 64

// The 16 byte aligned size of our uniform structures
let kAlignedSharedUniformsSize: Int = (MemoryLayout<SharedUniforms>.size & ~0xFF) + 0x100
let kAlignedInstanceUniformsSize: Int = ((MemoryLayout<InstanceUniforms>.size * kMaxAnchorInstanceCount) & ~0xFF) + 0x100

// Vertex data for an image plane
let kImagePlaneVertexData: [Float] = [
    -1.0, -1.0,  0.0, 1.0,
     1.0, -1.0,  1.0, 1.0,
     -1.0,  1.0,  0.0, 0.0,
     1.0,  1.0,  1.0, 0.0,
]
//... form ARMetal proj

let kSkinSmoothingFactor : Float = 0.6

let kSmoothingPasses: Int = 6

let kFaceIndexCount : Int = 2304 * 3

let smoothingPassSizes : [CGFloat] = [1.0,0.25,0.2,0.2,0.2]

let smoothingPassInstructions : [(Int, Bool)] = [ (1,true), (2,true), (3,true), (4,true), (2, false), (3,false), (0,true) ]

struct CameraInstrinsics {
    var fx : Float = 0.0
    var fy : Float = 0.0
    var cx : Float = 0.0
    var cy : Float = 0.0
}

//...end form ARMetal proj


class Renderer: NSObject, ARSessionDelegate  {
    let session: ARSession //+
    let device: MTLDevice  //+
    let inFlightSemaphore = DispatchSemaphore(value: kMaxBuffersInFlight) //+
    var renderDestination: RenderDestinationProvider //+
    
    // Metal objects
    var commandQueue: MTLCommandQueue!//+
    var sharedUniformBuffer: MTLBuffer!//+
    var anchorUniformBuffer: MTLBuffer!//+
    var imagePlaneVertexBuffer: MTLBuffer!//+
    var capturedImagePipelineState: MTLRenderPipelineState!//+
    var capturedImageDepthState: MTLDepthStencilState!//+
    var anchorPipelineState: MTLRenderPipelineState!//++ capturedImagePipelineState
    var anchorDepthState: MTLDepthStencilState!//++capturedImageDepthState
    //var capturedImageTextureY: CVMetalTexture? //++
    //var capturedImageTextureCbCr: CVMetalTexture?//++
    var capturedImageTextureY: MTLTexture? //++
    var capturedImageTextureCbCr: MTLTexture?//++
    
    // Captured image texture cache
    var capturedImageTextureCache: CVMetalTextureCache!//+
    
    // Metal vertex descriptor specifying how vertices will by laid out for input into our
    //   anchor geometry render pipeline and how we'll layout our Model IO vertices
    var geometryVertexDescriptor: MTLVertexDescriptor!//+
    
    // MetalKit mesh containing vertex data and index buffer for our anchor geometry
    var cubeMesh: MTKMesh!//-- commented
    
    // Used to determine _uniformBufferStride each frame.
    //   This is the current frame number modulo kMaxBuffersInFlight
    var uniformBufferIndex: Int = 0 //+
    
    // Offset within _sharedUniformBuffer to set for the current frame
    var sharedUniformBufferOffset: Int = 0//+
    
    // Offset within _anchorUniformBuffer to set for the current frame
    var anchorUniformBufferOffset: Int = 0//+
    
    // Addresses to write shared uniforms to each frame
    var sharedUniformBufferAddress: UnsafeMutableRawPointer! //+
    
    // Addresses to write anchor uniforms to each frame
    var anchorUniformBufferAddress: UnsafeMutableRawPointer!  //+
    
    // The number of anchor instances to render
    var anchorInstanceCount: Int = 0 //-- commented
    
    // The current viewport size
    var viewportSize: CGSize = CGSize() //+
    
    // Flag for viewport size changes
    var viewportSizeDidChange: Bool = false //+
    //.... add now from ARMetal proj
    var viewport : CGRect = CGRect(x: 0, y: 0, width: 1125, height: 2436)
    var sceneRenderer: SCNRenderer//+
    let ciContext: CIContext//+
    // MARK: Nodes
    let scene: SCNScene
    var worldNode : SCNNode?
    let cameraNode: SCNNode
    let lightNode : SCNNode!
    let ambientLightNode : SCNNode!
    var lastFaceTransform : matrix_float4x4?
    
    
    var colorProcessingParameters : ColorProcessingParameters!//+
    var cameraInstrinsics: CameraInstrinsics?
    var lastTimestamp : TimeInterval? //+
    var alternateFaceUVSource : SCNGeometrySource?//+
    var capturedImageRenderTextureBuffer : MTLTexture!//+
    var skinSmoothingTextureBuffers: [MTLTexture]!//+
    var skinSmoothingDepthBuffer: MTLTexture!//+
    
    var alternateFaceUVSourceCoords : [float2] = [float2]()//+
    var isSwappingMasks : Bool = false //+
    var pointOfViewConfigured: Bool = false//+
    var pixelBufferPool : CVPixelBufferPool?//+
    var outputFormatDescriptor : CMFormatDescription?//+
    var colorSpace : CGColorSpace?//+
    var lastCamera : ARCamera?//+
    var faceGeometry : ARFaceGeometry?//+
    var worldAnchor : ARAnchor?//+
    var worldAnchorUUID : UUID?//+
    var isTracking : Bool = false//+
    var pixelBufferConsumer: RenderPixelBufferConsumer?//+
    var outputPixelBufferAttributes : [String : Any]?//+
    var textureLoader : MTKTextureLoader!//+
    var faceMaskTexture : MTLTexture!//+
    var faceVertexBuffer: MTLBuffer!//+
    var faceTexCoordBuffer: MTLBuffer!//+
    var faceIndexBuffer: MTLBuffer!//+
    var cvPipelineState: MTLRenderPipelineState!//+
    var skinSmoothingPipelineState: MTLRenderPipelineState!//+
    var skinSmoothingDepthState: MTLDepthStencilState!//+
    var lutComputePipelineState: MTLComputePipelineState!//+
    var compositePipelineState: MTLRenderPipelineState!//+
    var colorProcessingPipelineState: MTLRenderPipelineState!//+
    var draw2DPipelineState: MTLRenderPipelineState!//+
    var scenePipelineState: MTLRenderPipelineState!//+
    var renderTargetTexture0 : MTLTexture?//++
    //var renderTargetTexture1 : MTLTexture?
    
    var faceContentNode: VirtualFaceNode? {//+
        willSet(newfaceContentNode) {
            
            isSwappingMasks = true
            self.faceContentNode?.isHidden = true
        }
        
        didSet {
            
            DispatchQueue.main.async {
                // self.worldNode?.removeFromParentNode()
                oldValue?.removeFromParentNode()
            }
            self.worldNode?.isHidden = true
            self.faceContentNode?.isHidden = true
            //   self.faceContentNode?.opacity = 0.0
            // self.worldNode = nil
            //            if let anchor = self.worldAnchor  {
            //            self.session.remove(anchor: anchor)
            //            }
            
            if self.faceContentNode != nil  {
                
                // var nodes = [SCNNode]()
                
                //               if let texCoordSource = self.faceContentNode!.geometry?.sources( for: SCNGeometrySource.Semantic.texcoord ) {
                //
                //                    print("found tex coords")
                //
                //                }
                if let overlayScene = self.faceContentNode?.overlaySKScene  {
                    self.sceneRenderer.overlaySKScene = overlayScene
                    self.sceneRenderer.overlaySKScene!.scaleMode = .aspectFill
                    
                } else {
                    self.sceneRenderer.overlaySKScene = nil
                }
                self.colorProcessingParameters = self.faceContentNode?.colorParameters
                if let worldNode = self.faceContentNode?.worldNode {
                    
                    //                    if  self.worldAnchor == nil {
                    //
                    //                        self.worldAnchor = ARAnchor(transform: matrix_identity_float4x4)
                    //
                    //                        self.worldAnchorUUID = self.worldAnchor?.identifier
                    //
                    //                        self.session.add(anchor: self.worldAnchor!)
                    //                    }
                    //self.session.add(anchor: self.worldAnchor!)
                    
                    // nodes.append(self.worldNode!)
                    
                    if self.worldNode != nil {
                        self.scene.rootNode.replaceChildNode(self.worldNode!, with: worldNode)
                    } else {
                        self.scene.rootNode.addChildNode(worldNode)
                    }
                    
                    self.worldNode = worldNode
                    
                    // self.scene.rootNode.addChildNode(self.worldNode!)
                    
                }
                
                //self.faceContentNode?.opacity = 0.0
                
                // nodes.append(self.faceContentNode!)
                
                self.scene.rootNode.addChildNode(self.faceContentNode!)
                //                for node in nodes {
                //                    self.scene.rootNode.addChildNode(node)
                //
                //                }
                
                
                //                sceneRenderer.prepare(nodes, completionHandler: { (result) in
                //
                //                    for node in nodes {
                //                        self.scene.rootNode.addChildNode(node)
                //
                //                    }
                //
                //                })
            }
            
            self.updateTextures()
            
            self.faceContentNode?.loadSpecialMaterials()
            
            isSwappingMasks = false
            
            self.faceContentNode?.isHidden = false
            
            
        }
    }
    //..end.. add now from ARMetal proj
    // MARK: Functionality
    
    init(session: ARSession, metalDevice device: MTLDevice, renderDestination: RenderDestinationProvider, sceneKitScene scene: SCNScene ) {
        
        // init(session: ARSession, metalDevice device: MTLDevice, renderDestination: RenderDestinationProvider) {
        self.session = session
        self.device = device
        self.renderDestination = renderDestination
        //..from ARMetal proj
        self.ciContext = CIContext(mtlDevice:self.device)
        self.textureLoader = MTKTextureLoader(device: device)
        
        self.scene = scene
        
        self.sceneRenderer = SCNRenderer(device: self.device, options: nil)
        self.sceneRenderer.autoenablesDefaultLighting = false
        self.sceneRenderer.isPlaying = true
        self.sceneRenderer.scene = self.scene
        let light = SCNLight()
        light.type = .directional
        light.color = UIColor.lightGray
        light.intensity = 1000
        
        self.lightNode = SCNNode()
        
        self.lightNode.light = light
        
        self.lightNode.position = SCNVector3Make(5.0, 5.0, 5.0)
        
        self.scene.rootNode.addChildNode(lightNode)
        
        
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = UIColor.white
        ambientLight.intensity = 1000
        
        self.ambientLightNode = SCNNode()
        
        self.ambientLightNode.light = light
        
        self.ambientLightNode.position = SCNVector3Make(0.0, 5.0, 0)
        
        self.scene.rootNode.addChildNode(self.ambientLightNode)
        
        
        self.cameraNode = SCNNode()
        
        self.cameraNode.camera = SCNCamera()
        
        self.scene.rootNode.addChildNode(self.cameraNode)
        self.sceneRenderer.pointOfView = self.cameraNode
        self.colorProcessingParameters = ColorProcessingParameters()
        
        self.worldAnchor = ARAnchor(transform: matrix_identity_float4x4)
        
        self.worldAnchorUUID = self.worldAnchor!.identifier
        
        self.session.add(anchor: self.worldAnchor!)
        
        if let uvPath = Bundle.main.url(forResource: "daz3duv", withExtension: "plist", subdirectory: nil) {
            
            let allValues =  NSArray(contentsOfFile: uvPath.path) as? [Float]
            
            var newUVCoords = [CGPoint]()
            
            let pairs = allValues!.count/2
            
            for i in 0..<pairs {
                
                let offset = i * 2
                let x = allValues![offset]
                let y = allValues![offset+1]
                
                alternateFaceUVSourceCoords.append(float2(x:x,y:y))
                
                newUVCoords.append(CGPoint(x:CGFloat(x),y:CGFloat(y)))
            }
            
            self.alternateFaceUVSource = SCNGeometrySource(textureCoordinates:newUVCoords)
        }
        
        //..end from ...
        super.init()
        loadMetal()
        loadAssets()
    }
    
    func drawRectResized(size: CGSize) {
        viewportSize = size
        viewport = CGRect(x: 0, y:0, width:size.width  , height: size.height )
        viewportSizeDidChange = true
        configurePointOfView()
    }
    func configurePointOfView()
    {
        sceneRenderer.pointOfView?.camera?.focalLength = 20.784610748291
         sceneRenderer.pointOfView?.camera?.sensorHeight = 24.0
         sceneRenderer.pointOfView?.camera?.fieldOfView = 60
         
         
         
         var newMatrix = SCNMatrix4Identity
         newMatrix.m11 = 3.223367
         newMatrix.m22 = 1.48860991
         newMatrix.m31 = 0.000830888748
         newMatrix.m32 = -0.00301241875
         newMatrix.m33 = -1.00000191
         newMatrix.m34 = -1.0
         newMatrix.m41 = 0.0
         newMatrix.m42 = 0.0
         newMatrix.m43 = -0.00200000196
         newMatrix.m44 = 0.0
         
         
         
         sceneRenderer.pointOfView?.camera?.projectionTransform = newMatrix
         
         var simdMatrix = matrix_float4x4()
         simdMatrix.columns.0 = float4(1, 0, 0, 0.0)
         simdMatrix.columns.1 = float4(0, 1, 0, 0.0)
         simdMatrix.columns.2 = float4(0, 0, 1, 0.0)
         simdMatrix.columns.3 = float4(0.0, 0.0, 0.0, 1.0)
         
         sceneRenderer.pointOfView?.simdTransform = simdMatrix
         
         sceneRenderer.pointOfView?.camera?.focalLength = 20.784610748291
         sceneRenderer.pointOfView?.camera?.sensorHeight = 24.0
         sceneRenderer.pointOfView?.camera?.fieldOfView = 60
         
         sceneRenderer.pointOfView?.camera?.automaticallyAdjustsZRange = true
         
         
         
         pointOfViewConfigured = true
    }
    
    func update() {
        // Wait to ensure only kMaxBuffersInFlight are getting processed by any stage in the Metal
        //   pipeline (App, Metal, Drivers, GPU, etc)
        let _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        //...inject from proj
        
        updateBufferStates()
        
        if !pointOfViewConfigured {
            if let _ = sceneRenderer.pointOfView   {
                self.configurePointOfView()
            }
        }
        
        var outputPixelBuffer : CVPixelBuffer?
        
        //var renderTargetTexture0 : MTLTexture?
        //var renderTargetTexture1 : MTLTexture?
        
        if pixelBufferPool != nil {
            var newPixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool!, &newPixelBuffer)
            if newPixelBuffer == nil  {
                print("Allocation failure: Could not get pixel buffer from pool (\(self.description))")
                return
            }
            
            outputPixelBuffer = newPixelBuffer
            
            
            
            if let outputTexture = createTexture(fromPixelBuffer: outputPixelBuffer!, pixelFormat: .bgra8Unorm, planeIndex: 0)
            {
                renderTargetTexture0 =    CVMetalTextureGetTexture(outputTexture)
            }
            // if let outputTexture = createTexture(fromPixelBuffer: outputPixelBuffer!, pixelFormat: .bgra8Unorm, planeIndex: 1)
            // {
            //     renderTargetTexture1 =    CVMetalTextureGetTexture(outputTexture)
            // }
            
            
        }
        
        
        //.....inject from project
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            commandBuffer.label = "MaskCommand"
            
            var textures = [capturedImageTextureY, capturedImageTextureCbCr]
            commandBuffer.addCompletedHandler{ [weak self] commandBuffer in
                if let strongSelf = self {
                    strongSelf.inFlightSemaphore.signal()
                }
                textures.removeAll()
            }
            
            
            
              if (renderTargetTexture0 != nil){
                  renderCVPixelBuffer22(commandBuffer: commandBuffer, destinationTexture: capturedImageTextureY!, noiseTextureSource: capturedImageTextureY!)
              }
            //  if (renderTargetTexture1 != nil){
            //     // renderCVPixelBuffer22(commandBuffer: commandBuffer, destinationTexture: capturedImageTextureCbCr2!, noiseTextureSource: renderTargetTexture1!)
            //  }
            
            renderCapturedImage(commandBuffer: commandBuffer)
            
            
            // .. late isSwappingMasks && capturedImageRenderTextureBuffe ,,,,,
            
            if let renderPassDescriptor = renderDestination.currentRenderPassDescriptor {
                
                let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
                
                renderEncoder.label = "BaseRenderEncoder"
                
                drawCapturedImage(renderEncoder: renderEncoder)
                
                renderEncoder.endEncoding()
                
                
                
                
                if lastCamera != nil && faceGeometry != nil && faceContentNode != nil && isTracking  && !isSwappingMasks{
                    renderSkinSmoothing(commandBuffer: commandBuffer, renderPassDescriptor: renderPassDescriptor)
                    renderImageComposite( commandBuffer: commandBuffer, destinationTexture:renderPassDescriptor.colorAttachments[0].texture!, compositeTexture: skinSmoothingTextureBuffers[0]   )
                    
                }
                else {
                    renderImageComposite( commandBuffer: commandBuffer, destinationTexture:renderPassDescriptor.colorAttachments[0].texture!, compositeTexture: capturedImageRenderTextureBuffer   )
                    
                }
                
                
                if isTracking && !isSwappingMasks {
                    renderImageComposite( commandBuffer: commandBuffer,destinationTexture: capturedImageRenderTextureBuffer, compositeTexture: skinSmoothingTextureBuffers[0]   )
                    faceContentNode?.updateCameraTexture(withCameraTexture: capturedImageRenderTextureBuffer )
                }
                
                
                if !isSwappingMasks {
                    let renderScenePassDescriptor = MTLRenderPassDescriptor()
                    
                    renderScenePassDescriptor.colorAttachments[0].texture =  renderPassDescriptor.colorAttachments[0].texture
                    renderScenePassDescriptor.colorAttachments[0].resolveTexture =  renderPassDescriptor.colorAttachments[0].resolveTexture;
                    renderScenePassDescriptor.colorAttachments[0].loadAction = MTLLoadAction.load;
                    renderScenePassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
                    renderScenePassDescriptor.colorAttachments[0].storeAction =  renderPassDescriptor.colorAttachments[0].storeAction;
                    renderScenePassDescriptor.depthAttachment = renderPassDescriptor.depthAttachment;
                    renderScenePassDescriptor.stencilAttachment = renderPassDescriptor.stencilAttachment;
                    
                    
                    sceneRenderer.render(atTime: CACurrentMediaTime(), viewport: viewport, commandBuffer: commandBuffer, passDescriptor: renderScenePassDescriptor)
                    
                    
                    if faceContentNode?.lutTextures[LUTType.world] != nil
                        || ( self.colorProcessingParameters.contrastIntensity != 0.0
                             && self.colorProcessingParameters.saturationIntensity != 1.0 ) {
                        renderColorProcessing( commandBuffer: commandBuffer, lutTexture: faceContentNode?.lutTextures[LUTType.world]!)
                    }
                    
                }
                
                
                //               if let lutTexture = faceContentNode?.lookUpTables()?[LUTType.world] {
                //
                //                    renderLUT(commandBuffer: commandBuffer, destinationTexture: renderPassDescriptor.colorAttachments[0].texture!, lutTexture: lutTexture, stencilTexture: //renderPassDescriptor.depthAttachment.texture!, lutType: LUTType.world)
                //
                //
                //               }
                
                if faceContentNode?.lutTextures[LUTType.world] != nil || ( self.colorProcessingParameters.contrastIntensity != 0.0 && self.colorProcessingParameters.saturationIntensity != 1.0 ) {
                    renderColorProcessing( commandBuffer: commandBuffer, lutTexture: faceContentNode?.lutTextures[LUTType.world]!)
                }
                
                
                // if faceContentNode?.lutTextures[LUTType.world] != nil || ( self.colorProcessingParameters.contrastIntensity != 0.0 && //self.colorProcessingParameters.saturationIntensity != 1.0 ) {
                // if (renderTargetTexture != nil)
                // {
                // renderImageCompositeDenois(commandBuffer:commandBuffer, destinationTexture: <#T##MTLTexture#><#T##MTLTexture#>, compositeTexture: <#T##MTLTexture#>)
                //( commandBuffer: commandBuffer, lutTexture: renderTargetTexture!)
                // }
                // }
                
                
                /* old one
                 if renderTargetTexture != nil {
                 
                 
                 
                 
                 //renderCVPixelBuffer(commandBuffer: commandBuffer, destinationTexture: renderTargetTexture!, sourceTexture: //renderPassDescriptor.colorAttachments[0].texture!)
                 
                 //if pixelBufferConsumer != nil {
                 //    pixelBufferConsumer!.renderCallbackQueue.async {
                 
                 //        let cmTime : CMTime = CMTimeMakeWithSeconds(self.lastTimestamp!, preferredTimescale: 1000000)
                 //        self.pixelBufferConsumer?.renderedOutput(didRender: outputPixelBuffer!, atTime: cmTime)
                 //    }
                 //}
                 }*/
                //...................................
                if pixelBufferConsumer != nil {
                    
                    renderCVPixelBuffer(commandBuffer: commandBuffer, destinationTexture: renderTargetTexture0!, sourceTexture: renderPassDescriptor.colorAttachments[0].texture!)
                    
                    pixelBufferConsumer!.renderCallbackQueue.async {
                        
                        
                        if let currentDrawable = self.renderDestination.currentDrawable {
                            // currentDrawable.texture
                            print( "hi")
                            var pixelBuffer: CVPixelBuffer?
                            
                            CVPixelBufferCreate( kCFAllocatorDefault,
                                                 currentDrawable.texture.width,
                                                 currentDrawable.texture.height,
                                                 // texture.width,
                                                 // texture.height,
                                                 kCVPixelFormatType_32BGRA,
                                                 nil,
                                                 &pixelBuffer)
                            
                            
                            CVPixelBufferLockBaseAddress( pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
                            let pixelBufferBytes = CVPixelBufferGetBaseAddress( pixelBuffer! )
                            let bytesPerRow = CVPixelBufferGetBytesPerRow( pixelBuffer! )
                            let region = MTLRegionMake2D(0, 0, currentDrawable.texture.width, currentDrawable.texture.height)
                            //currentDrawable.texture.
                            currentDrawable.texture.getBytes( pixelBufferBytes!, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
                            CVPixelBufferUnlockBaseAddress( pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
                            let cmTime : CMTime = CMTimeMakeWithSeconds(self.lastTimestamp!, preferredTimescale: 1000000)
                            self.pixelBufferConsumer?.renderedOutput(didRender: pixelBuffer!, atTime: cmTime)
                            
                        }
                        
                    }
                }
                
                
                
                
                //....................................
                
                if let currentDrawable = renderDestination.currentDrawable {
                    commandBuffer.present(currentDrawable)
                }
            }
            
            // Finalize rendering here & push the command buffer to the GPU
            commandBuffer.commit()
        }
        
        
        
        //...end ....
        // Create a new command buffer for each renderpass to the current drawable
        /* // if let commandBuffer = commandQueue.makeCommandBuffer() {
         //     commandBuffer.label = "MyCommand"
         
         // Add completion handler which signal _inFlightSemaphore when Metal and the GPU has fully
         //   finished processing the commands we're encoding this frame.  This indicates when the
         //   dynamic buffers, that we're writing to this frame, will no longer be needed by Metal
         //   and the GPU.
         // Retain our CVMetalTextures for the duration of the rendering cycle. The MTLTextures
         //   we use from the CVMetalTextures are not valid unless their parent CVMetalTextures
         //   are retained. Since we may release our CVMetalTexture ivars during the rendering
         //   cycle, we must retain them separately here.
         //       var textures = [capturedImageTextureY, capturedImageTextureCbCr]
         //        commandBuffer.addCompletedHandler{ [weak self] commandBuffer in
         //            if let strongSelf = self {
         //                strongSelf.inFlightSemaphore.signal()
         //            }
         //            textures.removeAll()
         //        }
         
         //       updateBufferStates()
         //       updateGameState()
         
         //       if let renderPassDescriptor = renderDestination.currentRenderPassDescriptor, let currentDrawable = renderDestination.currentDrawable, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
         
         //            renderEncoder.label = "MyRenderEncoder"
         
         //           drawCapturedImage(renderEncoder: renderEncoder)
         //           drawAnchorGeometry(renderEncoder: renderEncoder)
         
         //            // We're done encoding commands
         //            renderEncoder.endEncoding()
         
         // Schedule a present once the framebuffer is complete using the current drawable
         //            commandBuffer.present(currentDrawable)
         }
         
         //        // Finalize rendering here & push the command buffer to the GPU
         //        commandBuffer.commit()
         //    }*/
    }
    
    // MARK: - Private
    
    func loadMetal_originXcode() {
        // Create and load our basic Metal state objects
        
        // Set the default formats needed to render
        renderDestination.depthStencilPixelFormat = .depth32Float_stencil8
        renderDestination.colorPixelFormat = .bgra8Unorm
        renderDestination.sampleCount = 1
        
        // Calculate our uniform buffer sizes. We allocate kMaxBuffersInFlight instances for uniform
        //   storage in a single buffer. This allows us to update uniforms in a ring (i.e. triple
        //   buffer the uniforms) so that the GPU reads from one slot in the ring wil the CPU writes
        //   to another. Anchor uniforms should be specified with a max instance count for instancing.
        //   Also uniform storage must be aligned (to 256 bytes) to meet the requirements to be an
        //   argument in the constant address space of our shading functions.
        let sharedUniformBufferSize = kAlignedSharedUniformsSize * kMaxBuffersInFlight
        let anchorUniformBufferSize = kAlignedInstanceUniformsSize * kMaxBuffersInFlight
        
        // Create and allocate our uniform buffer objects. Indicate shared storage so that both the
        //   CPU can access the buffer
        sharedUniformBuffer = device.makeBuffer(length: sharedUniformBufferSize, options: .storageModeShared)
        sharedUniformBuffer.label = "SharedUniformBuffer"
        
        anchorUniformBuffer = device.makeBuffer(length: anchorUniformBufferSize, options: .storageModeShared)
        anchorUniformBuffer.label = "AnchorUniformBuffer"
        
        // Create a vertex buffer with our image plane vertex data.
        let imagePlaneVertexDataCount = kImagePlaneVertexData.count * MemoryLayout<Float>.size
        imagePlaneVertexBuffer = device.makeBuffer(bytes: kImagePlaneVertexData, length: imagePlaneVertexDataCount, options: [])
        imagePlaneVertexBuffer.label = "ImagePlaneVertexBuffer"
        
        // Load all the shader files with a metal file extension in the project
        let defaultLibrary = device.makeDefaultLibrary()!
        
        let capturedImageVertexFunction = defaultLibrary.makeFunction(name: "capturedImageVertexTransform")!
        let capturedImageFragmentFunction = defaultLibrary.makeFunction(name: "capturedImageFragmentShader")!
        
        // Create a vertex descriptor for our image plane vertex buffer
        let imagePlaneVertexDescriptor = MTLVertexDescriptor()
        
        // Positions.
        imagePlaneVertexDescriptor.attributes[0].format = .float2
        imagePlaneVertexDescriptor.attributes[0].offset = 0
        imagePlaneVertexDescriptor.attributes[0].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // Texture coordinates.
        imagePlaneVertexDescriptor.attributes[1].format = .float2
        imagePlaneVertexDescriptor.attributes[1].offset = 8
        imagePlaneVertexDescriptor.attributes[1].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // Buffer Layout
        imagePlaneVertexDescriptor.layouts[0].stride = 16
        imagePlaneVertexDescriptor.layouts[0].stepRate = 1
        imagePlaneVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        // Create a pipeline state for rendering the captured image
        let capturedImagePipelineStateDescriptor = MTLRenderPipelineDescriptor()
        capturedImagePipelineStateDescriptor.label = "MyCapturedImagePipeline"
        capturedImagePipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        capturedImagePipelineStateDescriptor.vertexFunction = capturedImageVertexFunction
        capturedImagePipelineStateDescriptor.fragmentFunction = capturedImageFragmentFunction
        capturedImagePipelineStateDescriptor.vertexDescriptor = imagePlaneVertexDescriptor
        capturedImagePipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        capturedImagePipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        capturedImagePipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        
        do {
            try capturedImagePipelineState = device.makeRenderPipelineState(descriptor: capturedImagePipelineStateDescriptor)
        } catch let error {
            print("Failed to created captured image pipeline state, error \(error)")
        }
        
        let capturedImageDepthStateDescriptor = MTLDepthStencilDescriptor()
        capturedImageDepthStateDescriptor.depthCompareFunction = .always
        capturedImageDepthStateDescriptor.isDepthWriteEnabled = false
        capturedImageDepthState = device.makeDepthStencilState(descriptor: capturedImageDepthStateDescriptor)
        
        // Create captured image texture cache
        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        capturedImageTextureCache = textureCache
        
        let anchorGeometryVertexFunction = defaultLibrary.makeFunction(name: "anchorGeometryVertexTransform")!
        let anchorGeometryFragmentFunction = defaultLibrary.makeFunction(name: "anchorGeometryFragmentLighting")!
        
        // Create a vertex descriptor for our Metal pipeline. Specifies the layout of vertices the
        //   pipeline should expect. The layout below keeps attributes used to calculate vertex shader
        //   output position separate (world position, skinning, tweening weights) separate from other
        //   attributes (texture coordinates, normals).  This generally maximizes pipeline efficiency
        geometryVertexDescriptor = MTLVertexDescriptor()
        
        // Positions.
        geometryVertexDescriptor.attributes[0].format = .float3
        geometryVertexDescriptor.attributes[0].offset = 0
        geometryVertexDescriptor.attributes[0].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // Texture coordinates.
        geometryVertexDescriptor.attributes[1].format = .float2
        geometryVertexDescriptor.attributes[1].offset = 0
        geometryVertexDescriptor.attributes[1].bufferIndex = Int(kBufferIndexMeshGenerics.rawValue)
        
        // Normals.
        geometryVertexDescriptor.attributes[2].format = .half3
        geometryVertexDescriptor.attributes[2].offset = 8
        geometryVertexDescriptor.attributes[2].bufferIndex = Int(kBufferIndexMeshGenerics.rawValue)
        
        // Position Buffer Layout
        geometryVertexDescriptor.layouts[0].stride = 12
        geometryVertexDescriptor.layouts[0].stepRate = 1
        geometryVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        // Generic Attribute Buffer Layout
        geometryVertexDescriptor.layouts[1].stride = 16
        geometryVertexDescriptor.layouts[1].stepRate = 1
        geometryVertexDescriptor.layouts[1].stepFunction = .perVertex
        
        // Create a reusable pipeline state for rendering anchor geometry
        let anchorPipelineStateDescriptor = MTLRenderPipelineDescriptor()
        anchorPipelineStateDescriptor.label = "MyAnchorPipeline"
        anchorPipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        anchorPipelineStateDescriptor.vertexFunction = anchorGeometryVertexFunction
        anchorPipelineStateDescriptor.fragmentFunction = anchorGeometryFragmentFunction
        anchorPipelineStateDescriptor.vertexDescriptor = geometryVertexDescriptor
        anchorPipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        anchorPipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        anchorPipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        
        do {
            try anchorPipelineState = device.makeRenderPipelineState(descriptor: anchorPipelineStateDescriptor)
        } catch let error {
            print("Failed to created anchor geometry pipeline state, error \(error)")
        }
        
        let anchorDepthStateDescriptor = MTLDepthStencilDescriptor()
        anchorDepthStateDescriptor.depthCompareFunction = .less
        anchorDepthStateDescriptor.isDepthWriteEnabled = true
        anchorDepthState = device.makeDepthStencilState(descriptor: anchorDepthStateDescriptor)
        
        // Create the command queue
        commandQueue = device.makeCommandQueue()
    }
    //...original xCode ...
    func loadAssets_originXcode() {
        // Create and load our assets into Metal objects including meshes and textures
        
        // Create a MetalKit mesh buffer allocator so that ModelIO will load mesh data directly into
        //   Metal buffers accessible by the GPU
        let metalAllocator = MTKMeshBufferAllocator(device: device)
        
        // Create a Model IO vertexDescriptor so that we format/layout our model IO mesh vertices to
        //   fit our Metal render pipeline's vertex descriptor layout
        let vertexDescriptor = MTKModelIOVertexDescriptorFromMetal(geometryVertexDescriptor)
        
        // Indicate how each Metal vertex descriptor attribute maps to each ModelIO attribute
        (vertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributePosition
        (vertexDescriptor.attributes[Int(kVertexAttributeTexcoord.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributeTextureCoordinate
        (vertexDescriptor.attributes[Int(kVertexAttributeNormal.rawValue)] as! MDLVertexAttribute).name   = MDLVertexAttributeNormal
        
        // Use ModelIO to create a box mesh as our object
        let mesh = MDLMesh(boxWithExtent: vector3(0.075, 0.075, 0.075), segments: vector3(1, 1, 1), inwardNormals: false, geometryType: .triangles, allocator: metalAllocator)
        
        // Perform the format/relayout of mesh vertices by setting the new vertex descriptor in our
        //   Model IO mesh
        mesh.vertexDescriptor = vertexDescriptor
        
        // Create a MetalKit mesh (and submeshes) backed by Metal buffers
        do {
            try cubeMesh = MTKMesh(mesh: mesh, device: device)
        } catch let error {
            print("Error creating MetalKit mesh, error \(error)")
        }
    }
    //end ...original xCode ...
    // origian from xcode
    // func updateBufferStates() {
    //     // Update the location(s) to which we'll write to in our dynamically changing Metal buffers for
    //     //   the current frame (i.e. update our slot in the ring buffer used for the current frame)
    //      uniformBufferIndex = (uniformBufferIndex + 1) % kMaxBuffersInFlight
    //      sharedUniformBufferOffset = kAlignedSharedUniformsSize * uniformBufferIndex
    //     anchorUniformBufferOffset = kAlignedInstanceUniformsSize * uniformBufferIndex
    //     sharedUniformBufferAddress = sharedUniformBuffer.contents().advanced(by: sharedUniformBufferOffset)
    //     anchorUniformBufferAddress = anchorUniformBuffer.contents().advanced(by: anchorUniformBufferOffset)
    //  }
    // origian from xcode
    // func updateGameState() {
    //     // Update any game state
    
    //     guard let currentFrame = session.currentFrame else {
    //        return
    //    }
    
    //    updateSharedUniforms(frame: currentFrame)
    //    updateAnchors(frame: currentFrame)
    //    updateCapturedImageTextures(frame: currentFrame)
    
    //    if viewportSizeDidChange {
    //        viewportSizeDidChange = false
    //
    //        updateImagePlane(frame: currentFrame)
    //    }
    // }
    
    // MARK: injection
    
    
    func loadMetal() {
        
        
        
        
        // Create and load our basic Metal state objects
        
        // Set the default formats needed to render
        renderDestination.depthStencilPixelFormat = .depth32Float_stencil8
        renderDestination.colorPixelFormat = .bgra8Unorm
        renderDestination.sampleCount = 1
        
        // Calculate our uniform buffer sizes. We allocate kMaxBuffersInFlight instances for uniform
        //   storage in a single buffer. This allows us to update uniforms in a ring (i.e. triple
        //   buffer the uniforms) so that the GPU reads from one slot in the ring wil the CPU writes
        //   to another. Anchor uniforms should be specified with a max instance count for instancing.
        //   Also uniform storage must be aligned (to 256 bytes) to meet the requirements to be an
        //   argument in the constant address space of our shading functions.
        let sharedUniformBufferSize = kAlignedSharedUniformsSize * kMaxBuffersInFlight
        //  let anchorUniformBufferSize = kAlignedInstanceUniformsSize * kMaxBuffersInFlight
        
        // Create and allocate our         let anchorUniformBufferSize = kAlignedInstanceUniformsSize * kMaxBuffersInFlight
        // uniform buffer objects. Indicate shared storage so that both the
        //   CPU can access the buffer
        sharedUniformBuffer = device.makeBuffer(length: sharedUniformBufferSize, options: .storageModeShared)
        sharedUniformBuffer.label = "SharedUniformBuffer"
        
        //        anchorUniformBuffer = device.makeBuffer(length: anchorUniformBufferSize, options: .storageModeShared)
        //        anchorUniformBuffer.label = "AnchorUniformBuffer"
        
        
        // Create a vertex buffer with our image plane vertex data.
        let imagePlaneVertexDataCount = kImagePlaneVertexData.count * MemoryLayout<Float>.size
        imagePlaneVertexBuffer = device.makeBuffer(bytes: kImagePlaneVertexData, length: imagePlaneVertexDataCount, options: [])
        imagePlaneVertexBuffer.label = "ImagePlaneVertexBuffer"
        
        
        // Load all the shader files with a metal file extension in the project
        let defaultLibrary = device.makeDefaultLibrary()!
        
        let capturedImageVertexFunction = defaultLibrary.makeFunction(name: "capturedImageVertexFunction")!
        let capturedImageFragmentFunction = defaultLibrary.makeFunction(name: "capturedImageFragmentFunction")!
        
        let cvImageVertexFunction = defaultLibrary.makeFunction(name: "cvVertexFunction")!
        let cvImageFragmentFunction = defaultLibrary.makeFunction(name: "cvFragmentFunction")!
        
        //        let lutVertexFunction = defaultLibrary.makeFunction(name: "lutVertexFunction")!
        //        let lutFragmentFunction = defaultLibrary.makeFunction(name: "lutFragmentFunction")!
        
        let compositeVertexFunction = defaultLibrary.makeFunction(name: "compositeVertexFunction")!
        
        let compositeFragmentFunction = defaultLibrary.makeFunction(name: "compositeFragmentFunction")
        
        let draw2DVertexFunction = defaultLibrary.makeFunction(name: "draw2DVertexFunction")!
        let draw2DFragmentFunction = defaultLibrary.makeFunction(name: "draw2DFragmentFunction")!
        
        let colorProcessingVertexFunction = defaultLibrary.makeFunction(name: "colorProcessingVertexFunction")!
        let colorProcessingFragmentFunction = defaultLibrary.makeFunction(name: "colorProcessingFragmentFunction")!
        
        let  lutKernelFunction = defaultLibrary.makeFunction(name: "lutKernel2" )
        
        
        // Create a vertex descriptor for our image plane vertex buffer
        let imagePlaneVertexDescriptor = MTLVertexDescriptor()
        
        // Positions.
        imagePlaneVertexDescriptor.attributes[0].format = .float2
        imagePlaneVertexDescriptor.attributes[0].offset = 0
        imagePlaneVertexDescriptor.attributes[0].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // Texture coordinates.
        imagePlaneVertexDescriptor.attributes[1].format = .float2
        imagePlaneVertexDescriptor.attributes[1].offset = 8
        imagePlaneVertexDescriptor.attributes[1].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // Buffer Layout
        imagePlaneVertexDescriptor.layouts[0].stride = 16
        imagePlaneVertexDescriptor.layouts[0].stepRate = 1
        imagePlaneVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        // Create a pipeline state for rendering the captured image
        let capturedImagePipelineStateDescriptor = MTLRenderPipelineDescriptor()
        capturedImagePipelineStateDescriptor.label = "CapturedImagePipeline"
        capturedImagePipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        capturedImagePipelineStateDescriptor.vertexFunction = capturedImageVertexFunction
        capturedImagePipelineStateDescriptor.fragmentFunction = capturedImageFragmentFunction
        capturedImagePipelineStateDescriptor.vertexDescriptor = imagePlaneVertexDescriptor
        capturedImagePipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        capturedImagePipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        capturedImagePipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        
        
        
        do {
            try capturedImagePipelineState = device.makeRenderPipelineState(descriptor: capturedImagePipelineStateDescriptor)
        } catch let error {
            print("Failed to created captured image pipeline state, error \(error)")
        }
        
        let capturedImageDepthStateDescriptor = MTLDepthStencilDescriptor()
        capturedImageDepthStateDescriptor.depthCompareFunction = .always
        capturedImageDepthStateDescriptor.isDepthWriteEnabled = false
        capturedImageDepthState = device.makeDepthStencilState(descriptor: capturedImageDepthStateDescriptor)
        
        // Create captured image texture cache
        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        capturedImageTextureCache = textureCache
        
        
        let cvPipelineStateDescriptor = MTLRenderPipelineDescriptor()
        cvPipelineStateDescriptor.label = "CVImagePipeline"
        cvPipelineStateDescriptor.sampleCount = 1
        cvPipelineStateDescriptor.vertexFunction = cvImageVertexFunction
        cvPipelineStateDescriptor.fragmentFunction = cvImageFragmentFunction
        cvPipelineStateDescriptor.vertexDescriptor = imagePlaneVertexDescriptor
        cvPipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            try cvPipelineState = device.makeRenderPipelineState(descriptor: cvPipelineStateDescriptor)
        } catch let error {
            print("Failed to created captured image pipeline state, error \(error)")
        }
        
        
        let draw2DVertexDescriptor = MTLVertexDescriptor()
        
        // Positions.
        draw2DVertexDescriptor.attributes[0].format = .float4
        draw2DVertexDescriptor.attributes[0].offset = 0
        draw2DVertexDescriptor.attributes[0].bufferIndex = 0
        
        
        // Buffer Layout
        draw2DVertexDescriptor.layouts[0].stride = 16
        draw2DVertexDescriptor.layouts[0].stepRate = 1
        draw2DVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        // Create a pipeline state for rendering the captured image
        let draw2DPipelineStateDescriptor = MTLRenderPipelineDescriptor()
        draw2DPipelineStateDescriptor.label = "2DImagePipeline"
        draw2DPipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        draw2DPipelineStateDescriptor.vertexFunction = draw2DVertexFunction
        draw2DPipelineStateDescriptor.fragmentFunction = draw2DFragmentFunction
        draw2DPipelineStateDescriptor.vertexDescriptor = draw2DVertexDescriptor
        draw2DPipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        
        
        do {
            try draw2DPipelineState = device.makeRenderPipelineState(descriptor: draw2DPipelineStateDescriptor)
        } catch let error {
            print("Failed to create 2d image pipeline state, error \(error)")
        }
        
        
        let colorProcessingPipelineStateDescriptor = MTLRenderPipelineDescriptor()
        colorProcessingPipelineStateDescriptor.label = "ColorProcessingPipelineState"
        colorProcessingPipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        colorProcessingPipelineStateDescriptor.vertexFunction = colorProcessingVertexFunction
        colorProcessingPipelineStateDescriptor.fragmentFunction = colorProcessingFragmentFunction
        colorProcessingPipelineStateDescriptor.vertexDescriptor = imagePlaneVertexDescriptor
        
        colorProcessingPipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        colorProcessingPipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = false
        
        //            colorProcessingPipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperation.add
        //            colorProcessingPipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperation.add
        //            colorProcessingPipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactor.one
        //            colorProcessingPipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactor.sourceAlpha
        //            colorProcessingPipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactor.oneMinusSourceAlpha
        //            colorProcessingPipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactor.oneMinusSourceAlpha
        
        //        colorProcessingPipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactor.one
        //        colorProcessingPipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactor.one
        //        colorProcessingPipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactor.oneMinusSourceAlpha
        //        colorProcessingPipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactor.destinationAlpha
        
        do {
            try colorProcessingPipelineState = device.makeRenderPipelineState(descriptor: colorProcessingPipelineStateDescriptor)
        } catch let error {
            print("Failed to create overlay image pipeline state, error \(error)")
        }
        
        
        // Create a pipeline state for rendering the captured image
        let compositePipelineStateDescriptor = MTLRenderPipelineDescriptor()
        compositePipelineStateDescriptor.label = "CompositeImagePipeline"
        compositePipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        compositePipelineStateDescriptor.vertexFunction = compositeVertexFunction
        compositePipelineStateDescriptor.fragmentFunction = compositeFragmentFunction
        compositePipelineStateDescriptor.vertexDescriptor = imagePlaneVertexDescriptor
        compositePipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        // compositePipelineStateDescriptor.colorAttachments[1].pixelFormat = renderDestination.colorPixelFormat
        //compositePipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = false
        
        do {
            try compositePipelineState = device.makeRenderPipelineState(descriptor: compositePipelineStateDescriptor)
        } catch let error {
            print("Failed to created captured image pipeline state, error \(error)")
        }
        
        
        
        let textureUrl = Bundle.main.url(forResource: "SkinSmoothingTexture", withExtension: "png", subdirectory: "Models.scnassets")
        
        do {
            try faceMaskTexture = textureLoader.newTexture(URL: textureUrl!, options: nil)
        } catch let error {
            print("Failed to created captured image pipeline state, error \(error)")
            faceMaskTexture = nil
        }
        
        
        let faceVertexDataCount = 1220 * MemoryLayout<float4>.size
        faceVertexBuffer = device.makeBuffer(length: faceVertexDataCount, options: .storageModeShared)
        faceVertexBuffer.label = "faceVertexBuffer"
        
        let faceTexCoordCount = 1220 *  MemoryLayout<float2>.size
        faceTexCoordBuffer = device.makeBuffer(length: faceTexCoordCount, options: .storageModeShared)
        faceTexCoordBuffer.label = "faceTexCoordBuffer"
        
        let faceIndexCount = kFaceIndexCount *  MemoryLayout<UInt16>.size
        faceIndexBuffer = device.makeBuffer(length: faceIndexCount, options: .storageModeShared)
        faceIndexBuffer.label = "faceIndexBuffer"
        
        // later Eye .....
        
        geometryVertexDescriptor = MTLVertexDescriptor()
        
        geometryVertexDescriptor.attributes[0].format = .float3
        geometryVertexDescriptor.attributes[0].offset = 0
        geometryVertexDescriptor.attributes[0].bufferIndex = 0
        
        geometryVertexDescriptor.attributes[1].format = .float2
        geometryVertexDescriptor.attributes[1].offset = 0
        geometryVertexDescriptor.attributes[1].bufferIndex = 1
        
        geometryVertexDescriptor.layouts[0].stride = 16
        geometryVertexDescriptor.layouts[0].stepRate = 1
        geometryVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        geometryVertexDescriptor.layouts[1].stride = 8
        geometryVertexDescriptor.layouts[1].stepRate = 1
        geometryVertexDescriptor.layouts[1].stepFunction = .perVertex
        
        
        let skinSmoothingVertexFunction = defaultLibrary.makeFunction(name: "retouchVertexFunction")!
        let skinSmoothingFragmentFunction = defaultLibrary.makeFunction(name: "retouchFragmentFunction")!
        
        // Create a reusable pipeline state for rendering anchor geometry
        let skinSmoothingPipelineStateDescriptor = MTLRenderPipelineDescriptor()
        skinSmoothingPipelineStateDescriptor.label = "SkinSmoothingPipeline"
        skinSmoothingPipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        skinSmoothingPipelineStateDescriptor.vertexDescriptor = geometryVertexDescriptor
        skinSmoothingPipelineStateDescriptor.vertexFunction = skinSmoothingVertexFunction
        skinSmoothingPipelineStateDescriptor.fragmentFunction = skinSmoothingFragmentFunction
        skinSmoothingPipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        skinSmoothingPipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = false
        //        skinSmoothingPipelineStateDescriptor.depthAttachmentPixelFormat = MTLPixelFormat.depth32Float_stencil8
        //        skinSmoothingPipelineStateDescriptor.stencilAttachmentPixelFormat = MTLPixelFormat.depth32Float_stencil8
        
        //        skinSmoothingPipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperation.add
        //        skinSmoothingPipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperation.add
        //        skinSmoothingPipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactor.one
        //        skinSmoothingPipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactor.one
        //        skinSmoothingPipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactor.zero
        //        skinSmoothingPipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactor.zero
        
        do {
            try skinSmoothingPipelineState = device.makeRenderPipelineState(descriptor: skinSmoothingPipelineStateDescriptor)
        } catch let error {
            print("Failed to created anchor geometry pipeline state, error \(error)")
        }
        
        do {
            try lutComputePipelineState = device.makeComputePipelineState(function: lutKernelFunction!)
        } catch let error {
            print("Failed to created lut compute kernel function, error \(error)")
        }
        
        
        //        let skinSmoothingStencilStateDescriptor = MTLStencilDescriptor()
        //        skinSmoothingStencilStateDescriptor.writeMask = 0xFF
        //        skinSmoothingStencilStateDescriptor.stencilCompareFunction = .always
        //       let skinSmoothingDepthStateDescriptor = MTLDepthStencilDescriptor()
        ////        skinSmoothingDepthStateDescriptor.depthCompareFunction = .always
        //        skinSmoothingDepthStateDescriptor.isDepthWriteEnabled = true
        ////        skinSmoothingDepthStateDescriptor.frontFaceStencil = skinSmoothingStencilStateDescriptor
        ////        skinSmoothingDepthStateDescriptor.backFaceStencil = skinSmoothingStencilStateDescriptor
        ////
        //         skinSmoothingDepthState = device.makeDepthStencilState(descriptor: skinSmoothingDepthStateDescriptor)
        ////
        
        updateTextures()
        
        // self.sobelFilter = MPSImageSobel(device:self.device)
        
        
        // Create the command queue
        commandQueue = device.makeCommandQueue()
    }
    
    func loadAssets() {
        
    }
    func updateSharedUniforms(frame: ARFrame) {
        // Update the shared uniforms of the frame
        
        let uniforms = sharedUniformBufferAddress.assumingMemoryBound(to: SharedUniforms.self)
        
        uniforms.pointee.viewMatrix = frame.camera.viewMatrix(for: .landscapeRight)
        uniforms.pointee.projectionMatrix = frame.camera.projectionMatrix(for: .landscapeRight, viewportSize: viewportSize, zNear: 0.001, zFar: 1000)
        
        // Set up lighting for the scene using the ambient intensity if provided
        var ambientIntensity: Float = 1.0
        
        if let lightEstimate = frame.lightEstimate {
            ambientIntensity = Float(lightEstimate.ambientIntensity) / 1000.0
        }
        
        let ambientLightColor: vector_float3 = vector3(0.5, 0.5, 0.5)
        uniforms.pointee.ambientLightColor = ambientLightColor * ambientIntensity
        
        var directionalLightDirection : vector_float3 = vector3(0.0, 0.0, -1.0)
        directionalLightDirection = simd_normalize(directionalLightDirection)
        uniforms.pointee.directionalLightDirection = directionalLightDirection
        
        let directionalLightColor: vector_float3 = vector3(0.6, 0.6, 0.6)
        uniforms.pointee.directionalLightColor = directionalLightColor * ambientIntensity
        
        uniforms.pointee.materialShininess = 30
    }
    
    func updateAnchors_originXcode(frame: ARFrame) {
        // Update the anchor uniform buffer with transforms of the current frame's anchors
        anchorInstanceCount = min(frame.anchors.count, kMaxAnchorInstanceCount)
        
        var anchorOffset: Int = 0
        if anchorInstanceCount == kMaxAnchorInstanceCount {
            anchorOffset = max(frame.anchors.count - kMaxAnchorInstanceCount, 0)
        }
        
        for index in 0..<anchorInstanceCount {
            let anchor = frame.anchors[index + anchorOffset]
            
            // Flip Z axis to convert geometry from right handed to left handed
            var coordinateSpaceTransform = matrix_identity_float4x4
            coordinateSpaceTransform.columns.2.z = -1.0
            
            let modelMatrix = simd_mul(anchor.transform, coordinateSpaceTransform)
            
            let anchorUniforms = anchorUniformBufferAddress.assumingMemoryBound(to: InstanceUniforms.self).advanced(by: index)
            anchorUniforms.pointee.modelMatrix = modelMatrix
        }
    }
    func updateAnchors(frame: ARFrame) {
        
        /**
         The camera intrinsics.
         @discussion The matrix has the following contents:
         fx 0   px
         0  fy  py
         0  0   1
         fx and fy are the focal length in pixels.
         px and py are the coordinates of the principal point in pixels.
         The origin is at the center of the upper-left pixel.
         */
        if isSwappingMasks {
            return
        }
        
        for index in 0..<frame.anchors.count {
            
            let anchor = frame.anchors[index]
            
            
            guard let faceAnchor = anchor as? ARFaceAnchor else {
                
                if worldNode != nil && worldAnchorUUID != nil && worldAnchorUUID! == anchor.identifier {
                    var coordinateSpaceTransform = matrix_identity_float4x4
                    coordinateSpaceTransform.columns.2.z = -1.0
                    
                    let modelMatrix = simd_mul(frame.camera.viewMatrix(for: .portrait),anchor.transform);
                    worldNode?.simdTransform = modelMatrix
                    // worldNode?.simdTransform =  simd_mul(frame.camera.viewMatrix(for: .portrait),anchor.transform);
                }
                continue;
            }
            
            if !faceAnchor.isTracked  {
                
                self.isTracking = false
                
                faceContentNode?.setTracking(isTracking: false)
                
                continue;
            }
            
            if cameraInstrinsics == nil {
                
                let intrinsics : matrix_float3x3 = frame.camera.intrinsics
                
                cameraInstrinsics = CameraInstrinsics()
                cameraInstrinsics!.fx = intrinsics[0][0]
                cameraInstrinsics!.fy = intrinsics[1][1]
                cameraInstrinsics!.cx = intrinsics[2][0]
                cameraInstrinsics!.cy = intrinsics[2][1]
                
                //  openCVWrapper.setIntrinsics( simd_float4(cameraInstrinsics!.fx,cameraInstrinsics!.fy,cameraInstrinsics!.cx,cameraInstrinsics!.cy) )
                
            }
            
            
            //let upVector =   simd_float3( frame.camera.transform[2][1], frame.camera.transform[2][2], frame.camera.transform[2][3] )
            
            //  print("upVector: \(upVector)")
            
            self.isTracking = true
            
            faceContentNode?.setTracking(isTracking: true)
            
            //            if let opacity = faceContentNode?.opacity {
            //
            //                self.isTracking = true
            //
            //                if( opacity == 0.0 )
            //                {
            //                    SCNTransaction.begin()
            //                    SCNTransaction.animationDuration = 0.3
            //                    faceContentNode?.opacity = 1.0
            //                    SCNTransaction.commit()
            //                }
            //
            //            }
            
            
            faceContentNode?.updateFaceAnchor(withFaceAnchor: faceAnchor)
            
            faceContentNode?.simdTransform = simd_mul(frame.camera.viewMatrix(for: .portrait),faceAnchor.transform);
            
            //  worldNode?.simdTransform = simd_mul(frame.camera.viewMatrix(for: .portrait),faceAnchor.transform);
            
            faceGeometry = faceAnchor.geometry
            
            
            //            var geometryPtr : SCNGeometry = faceContentNode!.geometry!
            //
            //            var sources = geometryPtr.sources
            //
            //            var texSource = geometryPtr.sources(for: SCNGeometrySource.Semantic.texcoord)[0]
            //
            //            let dataLength = texSource.data.count
            //
            //            let testPointer = UnsafeRawBufferPointer(start: faceGeometry!.textureCoordinates, count: faceGeometry!.textureCoordinates.count * MemoryLayout<float2>.size )
            //
            //            var uvPointer = UnsafeRawBufferPointer(start: alternateFaceUVSourceCoords, count: faceGeometry!.textureCoordinates.count * MemoryLayout<float2>.size )
            //
            //            let mutablePointer = UnsafeMutableRawBufferPointer(mutating: testPointer)
            //
            //            mutablePointer.copyBytes(from: uvPointer)
            
            //            var bufferPointer = UnsafeMutableRawBufferPointer(start: &faceGeometry!.textureCoordinates, count: faceGeometry!.textureCoordinates.count * MemoryLayout<float2>.size )
            //
            //            var uvPointer = UnsafeRawBufferPointer(start: alternateFaceUVSourceCoords!, count: faceGeometry!.textureCoordinates.count * MemoryLayout<float2>.size )
            //
            // bufferPointer.
            
            
            lastFaceTransform = faceAnchor.transform
            
            
            // later needsEyeUpdate ..... if faceContentNode!.needsEyeUpdate

            
            
            //    maskNode.boundingBox
            //   cameraNode.position = cameraPos;
        }
    }

    func updateCapturedImageTextures(frame: ARFrame) {
        // Create two textures (Y and CbCr) from the provided frame's captured image
        let pixelBuffer = frame.capturedImage
        
        if (CVPixelBufferGetPlaneCount(pixelBuffer) < 2) {
            return
        }
        
        //capturedImageTextureY = createTexture(fromPixelBuffer: pixelBuffer, pixelFormat:.r8Unorm, planeIndex:0)
        //capturedImageTextureCbCr = createTexture(fromPixelBuffer: pixelBuffer, pixelFormat:.rg8Unorm, planeIndex:1)
        capturedImageTextureY = CVMetalTextureGetTexture(createTexture(fromPixelBuffer: pixelBuffer, pixelFormat:.r8Unorm, planeIndex:0)!)
        capturedImageTextureCbCr = CVMetalTextureGetTexture(createTexture(fromPixelBuffer: pixelBuffer, pixelFormat:.rg8Unorm, planeIndex:1)!)
        
    }
    
    func createTexture(fromPixelBuffer pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int) -> CVMetalTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        
        var texture: CVMetalTexture? = nil
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, capturedImageTextureCache, pixelBuffer, nil, pixelFormat, width, height, planeIndex, &texture)
        
        if status != kCVReturnSuccess {
            texture = nil
        }
        
        return texture
    }
    
    func updateImagePlane(frame: ARFrame) {
        // Update the texture coordinates of our image plane to aspect fill the viewport
        let displayToCameraTransform = frame.displayTransform(for: .portrait, viewportSize: viewportSize).inverted()
        
        let vertexData = imagePlaneVertexBuffer.contents().assumingMemoryBound(to: Float.self)
        for index in 0...3 {
            let textureCoordIndex = 4 * index + 2
            let textureCoord = CGPoint(x: CGFloat(kImagePlaneVertexData[textureCoordIndex]), y: CGFloat(kImagePlaneVertexData[textureCoordIndex + 1]))
            let transformedCoord = textureCoord.applying(displayToCameraTransform)
            vertexData[textureCoordIndex] = Float(transformedCoord.x)
            vertexData[textureCoordIndex + 1] = Float(transformedCoord.y)
        }
    }
    //origin from xcode
    func drawCapturedImage(renderEncoder: MTLRenderCommandEncoder) {
        guard let textureY = capturedImageTextureY, let textureCbCr = capturedImageTextureCbCr else {
            return
        }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("DrawCapturedImage")
        
        // Set render command encoder state
        renderEncoder.setCullMode(.none)
        renderEncoder.setRenderPipelineState(capturedImagePipelineState)
        renderEncoder.setDepthStencilState(capturedImageDepthState)
        
        // Set mesh's vertex buffers
        renderEncoder.setVertexBuffer(imagePlaneVertexBuffer, offset: 0, index: Int(kBufferIndexMeshPositions.rawValue))
        
        // Set any textures read/sampled from our render pipeline
        renderEncoder.setFragmentTexture(textureY, index: Int(kTextureIndexY.rawValue))
        //        renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(textureCbCr, index: Int(kTextureIndexCbCr.rawValue))
        
        renderEncoder.setFragmentTexture(textureCbCr, index: Int(kTextureIndexCbCr.rawValue))
        
        // Draw each submesh of our mesh
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        renderEncoder.popDebugGroup()
    }
    
    func drawAnchorGeometry(renderEncoder: MTLRenderCommandEncoder) {
        guard anchorInstanceCount > 0 else {
            return
        }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("DrawAnchors")
        
        // Set render command encoder state
        renderEncoder.setCullMode(.back)
        renderEncoder.setRenderPipelineState(anchorPipelineState)
        renderEncoder.setDepthStencilState(anchorDepthState)
        
        // Set any buffers fed into our render pipeline
        renderEncoder.setVertexBuffer(anchorUniformBuffer, offset: anchorUniformBufferOffset, index: Int(kBufferIndexInstanceUniforms.rawValue))
        renderEncoder.setVertexBuffer(sharedUniformBuffer, offset: sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
        renderEncoder.setFragmentBuffer(sharedUniformBuffer, offset: sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
        
        // Set mesh's vertex buffers
        for bufferIndex in 0..<cubeMesh.vertexBuffers.count {
            let vertexBuffer = cubeMesh.vertexBuffers[bufferIndex]
            renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index:bufferIndex)
        }
        
        // Draw each submesh of our mesh
        for submesh in cubeMesh.submeshes {
            renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: submesh.indexBuffer.offset, instanceCount: anchorInstanceCount)
        }
        
        renderEncoder.popDebugGroup()
    }
    
    
    func updateTextures()
    {
        
        var textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: renderDestination.colorPixelFormat, width: Int(viewport.width), height: Int(viewport.height), mipmapped: renderDestination.sampleCount > 0)
        
        textureDescriptor.usage = MTLTextureUsage(rawValue:MTLTextureUsage.shaderRead.rawValue  | MTLTextureUsage.shaderWrite.rawValue  | MTLTextureUsage.renderTarget.rawValue)
        
        capturedImageRenderTextureBuffer =  device.makeTexture(descriptor: textureDescriptor)!
        
        capturedImageRenderTextureBuffer.label = "capturedImageRenderTextureBuffer"
        
        skinSmoothingTextureBuffers = [MTLTexture]()
        
        
        for size : CGFloat in smoothingPassSizes {
            
            textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: renderDestination.colorPixelFormat, width: Int( Double(viewport.width * size).rounded(.up)), height: Int(Double(viewport.height * size).rounded(.up)), mipmapped: renderDestination.sampleCount > 0)
            
            textureDescriptor.usage = MTLTextureUsage(rawValue:MTLTextureUsage.shaderRead.rawValue | MTLTextureUsage.shaderWrite.rawValue | MTLTextureUsage.renderTarget.rawValue)
            
            if let smoothingPassBuffer =  device.makeTexture(descriptor: textureDescriptor) {
                skinSmoothingTextureBuffers.append(smoothingPassBuffer)
            }
            
        }
        
        textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: MTLPixelFormat.depth32Float_stencil8, width: Int(viewport.width), height: Int(viewport.height), mipmapped: renderDestination.sampleCount > 0)
        
        textureDescriptor.usage = MTLTextureUsage(rawValue:MTLTextureUsage.shaderRead.rawValue | MTLTextureUsage.shaderWrite.rawValue | MTLTextureUsage.renderTarget.rawValue)
        
        skinSmoothingDepthBuffer = device.makeTexture(descriptor: textureDescriptor)
    }
    
    
    func updateBufferStates() {
        // Update the location(s) to which we'll write to in our dynamically changing Metal buffers for
        //   the current frame (i.e. update our slot in the ring buffer used for the current frame)
        
        uniformBufferIndex = (uniformBufferIndex + 1) % kMaxBuffersInFlight
        
        sharedUniformBufferOffset = kAlignedSharedUniformsSize * uniformBufferIndex
        
        sharedUniformBufferAddress = sharedUniformBuffer.contents().advanced(by: sharedUniformBufferOffset)
        
    }
    
    
    func renderCapturedImage(commandBuffer : MTLCommandBuffer) {
        guard let textureY = capturedImageTextureY, let textureCbCr = capturedImageTextureCbCr else {
            return
        }
        
        let capturedImagePassDescriptor = MTLRenderPassDescriptor()
        
        capturedImagePassDescriptor.colorAttachments[0].texture = capturedImageRenderTextureBuffer
        capturedImagePassDescriptor.colorAttachments[0].loadAction = MTLLoadAction.dontCare;
        capturedImagePassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
        capturedImagePassDescriptor.colorAttachments[0].storeAction =  MTLStoreAction.store
        capturedImagePassDescriptor.colorAttachments[0].resolveTexture = renderDestination.currentRenderPassDescriptor?.colorAttachments[0].resolveTexture
        capturedImagePassDescriptor.stencilAttachment =  renderDestination.currentRenderPassDescriptor?.stencilAttachment
        capturedImagePassDescriptor.depthAttachment =  renderDestination.currentRenderPassDescriptor?.depthAttachment
        
        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: capturedImagePassDescriptor) {
            
            renderEncoder.pushDebugGroup("RenderCapturedImage")
            
            // Set render command encoder state
            renderEncoder.setCullMode(.none)
            renderEncoder.setRenderPipelineState(capturedImagePipelineState)
            renderEncoder.setDepthStencilState(capturedImageDepthState)
            
            // Set mesh's vertex buffers
            renderEncoder.setVertexBuffer(imagePlaneVertexBuffer, offset: 0, index: Int(kBufferIndexMeshPositions.rawValue))
            
            // Set any textures read/sampled from our render pipeline
            renderEncoder.setFragmentTexture(textureY as! MTLTexture, index: Int(kTextureIndexY.rawValue))
            renderEncoder.setFragmentTexture(textureCbCr as! MTLTexture, index: Int(kTextureIndexCbCr.rawValue))
            
            // Draw each submesh of our mesh
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            
            renderEncoder.popDebugGroup()
            
            
            renderEncoder.endEncoding()
            
        }
        
    }
    
    
    func createSmoothingPassParameters( passIndex: UInt32, sizeIndex: Int) -> (viewport : MTLViewport, parameters: SmoothingParameters) {
        
        let width : Double = Double(self.viewport.width * smoothingPassSizes[sizeIndex]).rounded(.up)
        
        let height : Double = Double(self.viewport.height * smoothingPassSizes[sizeIndex]).rounded(.up)
        
        let renderViewport = MTLViewport(originX:0,originY: 0,width: width,height: height,znear:0.0,zfar:1.0)
        
        var parameters = SmoothingParameters()
        parameters.skinSmoothingFactor = kSkinSmoothingFactor
        parameters.viewMatrix = self.lastCamera!.viewMatrix(for: .portrait)
        parameters.modelMatrix = faceContentNode!.simdTransform
        parameters.passIndex = passIndex
        parameters.imageSize = vector2( Float(renderViewport.width), Float(renderViewport.height) )
        parameters.renderSize = vector2( Float(renderViewport.width), Float(renderViewport.height) )
        parameters.projectionMatrix = self.lastCamera!.projectionMatrix(for: .portrait, viewportSize: CGSize(width:renderViewport.width,height:renderViewport.height), zNear: 0.001, zFar: 1000)
        parameters.inverseResolution = simd_recip( vector_float2( Float(renderViewport.width), Float(renderViewport.height) ) )
        
        //  print("renderViewport \(renderViewport) for passIndex \(passIndex)")
        return (renderViewport, parameters)
    }
    func renderSkinSmoothing( commandBuffer : MTLCommandBuffer, renderPassDescriptor : MTLRenderPassDescriptor )
    {
        
        commandBuffer.pushDebugGroup("SkinSmoothing")
        
        let clearColor = MTLClearColorMake(0.0,0.0,0.0, 0.0)
        
        
        faceVertexBuffer.contents().copyMemory(from: faceGeometry!.vertices, byteCount: 1220 * MemoryLayout<vector_float3>.size)
        
        faceTexCoordBuffer.contents().copyMemory(from: faceGeometry!.textureCoordinates, byteCount: 1220 * MemoryLayout<vector_float2>.size)
        
        faceIndexBuffer.contents().copyMemory(from: faceGeometry!.triangleIndices, byteCount: kFaceIndexCount * 2 )
        
        let textures = [capturedImageRenderTextureBuffer,
                        faceMaskTexture,
                        skinSmoothingTextureBuffers[1],
                        skinSmoothingTextureBuffers[2],
                        skinSmoothingTextureBuffers[3],
                        skinSmoothingTextureBuffers[4]
        ]
        
        // var passIndex : UInt32 = 0
        
        for ( passIndex, (bufferIndex,clearBuffer)) in smoothingPassInstructions.enumerated() {
            
            let renderSmoothingPassDescriptor = MTLRenderPassDescriptor()
            
            renderSmoothingPassDescriptor.colorAttachments[0].texture =  skinSmoothingTextureBuffers[bufferIndex]
            
            renderSmoothingPassDescriptor.colorAttachments[0].loadAction = clearBuffer ? MTLLoadAction.clear : MTLLoadAction.load
            renderSmoothingPassDescriptor.colorAttachments[0].clearColor = clearColor
            renderSmoothingPassDescriptor.colorAttachments[0].storeAction =  MTLStoreAction.store
            
            
            
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderSmoothingPassDescriptor)!
            
            renderEncoder.pushDebugGroup("Pass \(passIndex)")
            
            var passParameters = createSmoothingPassParameters(passIndex:UInt32(passIndex),sizeIndex:bufferIndex)
            
            renderEncoder.setViewport(passParameters.viewport)
            renderEncoder.setRenderPipelineState(skinSmoothingPipelineState)
            renderEncoder.setVertexBytes(&passParameters.parameters, length: MemoryLayout<SmoothingParameters>.size, index: 2)
            renderEncoder.setFragmentBytes(&passParameters.parameters, length: MemoryLayout<SmoothingParameters>.size, index: 2)
            renderEncoder.setVertexBuffer(faceVertexBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBuffer(faceTexCoordBuffer, offset: 0, index: 1)
            renderEncoder.setFragmentTextures(textures,  range: 0..<6 )
            renderEncoder.drawIndexedPrimitives(type: MTLPrimitiveType.triangle, indexCount: kFaceIndexCount, indexType: MTLIndexType.uint16, indexBuffer: faceIndexBuffer, indexBufferOffset: 0, instanceCount: 1)
            
            
            renderEncoder.popDebugGroup()
            
            renderEncoder.endEncoding()
        }
        
        
        
        commandBuffer.popDebugGroup()
        
    }
    
    func renderImageComposite( commandBuffer : MTLCommandBuffer, destinationTexture : MTLTexture, compositeTexture : MTLTexture ) {
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        
        renderPassDescriptor.colorAttachments[0].texture = destinationTexture
        renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadAction.load
        renderPassDescriptor.colorAttachments[0].storeAction =  MTLStoreAction.store
        renderPassDescriptor.colorAttachments[0].resolveTexture = renderDestination.currentRenderPassDescriptor?.colorAttachments[0].resolveTexture
        
        
        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            
            renderEncoder.pushDebugGroup("DrawCompositeImage")
            
            let renderViewport = MTLViewport(originX:0,originY: 0,width: Double( viewport.width ), height: Double( viewport.height ), znear:0.0,zfar:1.0)
            
            renderEncoder.setViewport(renderViewport)
            
            renderEncoder.setRenderPipelineState(compositePipelineState)
            
            renderEncoder.setVertexBuffer(imagePlaneVertexBuffer, offset: 0, index: Int(kBufferIndexMeshPositions.rawValue))
            
            renderEncoder.setFragmentTexture(compositeTexture, index: 0)
            
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            
            renderEncoder.popDebugGroup()
            
            renderEncoder.endEncoding()
            
        }
        
        
    }
    func renderColorProcessing( commandBuffer : MTLCommandBuffer,  lutTexture : MTLTexture?  ) {
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        
        renderPassDescriptor.colorAttachments[0].texture = renderDestination.currentRenderPassDescriptor?.colorAttachments[0].texture
        renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadAction.load
        renderPassDescriptor.colorAttachments[0].storeAction =  MTLStoreAction.store
        //   renderPassDescriptor.colorAttachments[0].resolveTexture = renderDestination.currentRenderPassDescriptor?.colorAttachments[0].resolveTexture
        
        
        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            
            renderEncoder.pushDebugGroup("ColorProcessing")
            
            renderEncoder.setCullMode(.none)
            
            renderEncoder.setRenderPipelineState(colorProcessingPipelineState)
            
            renderEncoder.setVertexBuffer(imagePlaneVertexBuffer, offset: 0, index: Int(kBufferIndexMeshPositions.rawValue))
            
            if let lut = lutTexture {
                renderEncoder.setFragmentTexture( lut, index: 0)
            }
            
            var parameters = ColorProcessingParameters()
            parameters.lutIntensity = self.colorProcessingParameters.lutIntensity
            parameters.saturationIntensity = self.colorProcessingParameters.saturationIntensity
            parameters.contrastIntensity = self.colorProcessingParameters.contrastIntensity
            
            renderEncoder.setFragmentBytes(&parameters, length: MemoryLayout<ColorProcessingParameters>.size, index: 0)
            
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            
            renderEncoder.popDebugGroup()
            
            renderEncoder.endEncoding()
            
        }
        
    }
    func renderCVPixelBuffer( commandBuffer : MTLCommandBuffer, destinationTexture : MTLTexture, sourceTexture : MTLTexture ) {
        
        //        let origin : MTLOrigin = MTLOriginMake(0, 0, 0)
        //        let size = MTLSizeMake(Int(1280), Int(720), 1)
        let clearColor = MTLClearColorMake(0.0,0.0,0.0, 0.0)
        //
        let cvImagePassDescriptor = MTLRenderPassDescriptor()
        
        
        cvImagePassDescriptor.colorAttachments[0].texture = destinationTexture
        cvImagePassDescriptor.colorAttachments[0].loadAction = MTLLoadAction.dontCare
        cvImagePassDescriptor.colorAttachments[0].clearColor = clearColor
        cvImagePassDescriptor.colorAttachments[0].storeAction =  MTLStoreAction.store
        
        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: cvImagePassDescriptor) {
            
            renderEncoder.pushDebugGroup("DrawCVImage")
            
            // Set render command encoder state
            renderEncoder.setCullMode(.none)
            
            let renderViewport = MTLViewport(originX:0,originY: 0,width: 1280,height: 720,znear:0.0,zfar:1.0)
            
            renderEncoder.setViewport(renderViewport)
            
            renderEncoder.setRenderPipelineState(cvPipelineState)
            
            // Set mesh's vertex buffers
            renderEncoder.setVertexBuffer(imagePlaneVertexBuffer, offset: 0, index: Int(kBufferIndexMeshPositions.rawValue))
            
            // Set any textures read/sampled from our render pipeline
            renderEncoder.setFragmentTexture(sourceTexture, index: 0)
            
            // Draw each submesh of our mesh
            //????
            //renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            
            renderEncoder.popDebugGroup()
            
            
            renderEncoder.endEncoding()
            
        }
    }
    func updateARFrame( currentFrame: ARFrame ) {
        
        
       // lastPixelBuffer = currentFrame.capturedImage
        
        lastTimestamp = currentFrame.timestamp
        
        updateSharedUniforms(frame: currentFrame)
        updateAnchors(frame: currentFrame)
        updateCapturedImageTextures(frame: currentFrame)
        
        if( self.pixelBufferPool == nil )
        {
            setupPixelBufferPool(frame: currentFrame)
        }
        
        updateLights(frame: currentFrame)
        
        if viewportSizeDidChange {
            viewportSizeDidChange = false
            updateTextures()
            updateImagePlane(frame: currentFrame)
        }
        
        
        
        // self.overlayNode.simdPosition = self.cameraNode.presentation.simdWorldFront * 0.825
        
    }
    func renderCVPixelBuffer22( commandBuffer : MTLCommandBuffer,  destinationTexture : MTLTexture , noiseTextureSource : MTLTexture) {
        

        if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            
            computeEncoder.setComputePipelineState(lutComputePipelineState)
            
            var intensity : Float =  Float(1)
            
            computeEncoder.setTexture(destinationTexture, index: 1)
            computeEncoder.setTexture(noiseTextureSource, index: 0)
            //computeEncoder.setBytes( &intensity, length: MemoryLayout<Float>.size, index: 0)
            
            let threadsPerGrid = MTLSize(width: destinationTexture.width,
                                         height: destinationTexture.height,
                                         depth: 1)
            
            let w = lutComputePipelineState.threadExecutionWidth
            
            let threadsPerThreadgroup = MTLSizeMake(w, lutComputePipelineState.maxTotalThreadsPerThreadgroup / w, 1)
            
            computeEncoder.dispatchThreads(threadsPerGrid,
                                           threadsPerThreadgroup: threadsPerThreadgroup)
            
            computeEncoder.endEncoding()
        }
        
    }
    func updateLights( frame: ARFrame ) {
        
        
        let lightEstimate = frame.lightEstimate!
        
        if let directionalLightEstimate = lightEstimate as? ARDirectionalLightEstimate {
            
            if var data = self.lightNode.light?.sphericalHarmonicsCoefficients {
                
                let coeffecients = directionalLightEstimate.sphericalHarmonicsCoefficients
                
                data.replaceSubrange(data.indices, with: coeffecients)
                
            }
            
            self.lightNode.light?.intensity = directionalLightEstimate.primaryLightIntensity
            
            self.lightNode.light?.temperature = lightEstimate.ambientColorTemperature
            
            
            self.ambientLightNode.light?.intensity =  directionalLightEstimate.primaryLightIntensity ;
            self.ambientLightNode.light?.temperature =  lightEstimate.ambientColorTemperature
            
            let primaryLightDirection : vector_float3 = normalize(directionalLightEstimate.primaryLightDirection)
            
            let lightVector = SCNVector3Make(primaryLightDirection.x, primaryLightDirection.y, primaryLightDirection.z)
            
            self.lightNode.eulerAngles =  lightVector
            
        }
        
        let intensity = lightEstimate.ambientIntensity / 1000.0;
        self.scene.lightingEnvironment.intensity = intensity
        
        
        
    }

    
    
    func setupPixelBufferPool(frame: ARFrame) {
        
        let pixelBuffer = frame.capturedImage;
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        
        
        //  let formatType = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        //let formatDescription = CVPixelFormatDescriptionCreateWithPixelFormatType(kCFAllocatorDefault, formatType)
        
        let pixelBufferAttributes : [String : Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                                      kCVPixelBufferWidthKey as String: width,
                                                      kCVPixelBufferHeightKey as String: height,
                                                      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                                                      kCVPixelBufferOpenGLESCompatibilityKey as String: true,
                                                      kCVPixelBufferIOSurfaceOpenGLESFBOCompatibilityKey as String: true,
                                                      kCVPixelBufferIOSurfaceCoreAnimationCompatibilityKey as String: true,
                                                      
                                                      kCVPixelBufferMetalCompatibilityKey as String: true]
        
        var inputFormatDescription : CMFormatDescription?
        
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: frame.capturedImage, formatDescriptionOut: &inputFormatDescription)
        
        colorSpace = CGColorSpaceCreateDeviceRGB()
        
        if let inputFormatDescriptionExtension = CMFormatDescriptionGetExtensions(inputFormatDescription!) as Dictionary? {
            let colorPrimaries = inputFormatDescriptionExtension[kCVImageBufferColorPrimariesKey]
            
            if let colorPrimaries = colorPrimaries {
                var colorSpaceProperties: [CFString: Any] = [kCVImageBufferColorPrimariesKey: colorPrimaries]
                
                if let yCbCrMatrix = inputFormatDescriptionExtension[kCVImageBufferYCbCrMatrixKey] {
                    colorSpaceProperties[kCVImageBufferYCbCrMatrixKey] = yCbCrMatrix
                }
                
                if let transferFunction = inputFormatDescriptionExtension[kCVImageBufferTransferFunctionKey] {
                    colorSpaceProperties[kCVImageBufferTransferFunctionKey] = transferFunction
                }
                
                //   pixelBufferAttributes[kCVBufferPropagatedAttachmentsKey as String] = colorSpaceProperties
            }
            
            if let cvColorSpace = inputFormatDescriptionExtension[kCVImageBufferCGColorSpaceKey] {
                colorSpace = cvColorSpace as! CGColorSpace
            } else if (colorPrimaries as? String) == (kCVImageBufferColorPrimaries_P3_D65 as String) {
                colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
            }
        }
        
        
        
        
        let poolOptions : [CFString : Any] = [kCVPixelBufferPoolMinimumBufferCountKey: 3]
        
        pixelBufferPool = nil
        
        CVPixelBufferPoolCreate(kCFAllocatorDefault, poolOptions as CFDictionary, pixelBufferAttributes as CFDictionary, &pixelBufferPool)
        
        guard let pixelBufferPool = pixelBufferPool else {
            assertionFailure("Allocation failure: Could not allocate pixel buffer pool")
            return
        }
        
        let poolAuxOptions : [CFString : Any] = [kCVPixelBufferPoolAllocationThresholdKey: 3]
        
        var testBuffer : CVPixelBuffer?
        
        CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pixelBufferPool, poolAuxOptions as CFDictionary, &testBuffer)
        
        preallocateBuffers(pool: pixelBufferPool, attributes: poolAuxOptions as CFDictionary)
        
        
        
        outputFormatDescriptor = nil
        
        if let testBuffer = testBuffer {
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: testBuffer, formatDescriptionOut: &outputFormatDescriptor)
            
        }
        
        
        self.outputPixelBufferAttributes = pixelBufferAttributes
        
        //pixelBufferPool = CVPixelBufferPool(
        
    }

    func preallocateBuffers( pool : CVPixelBufferPool, attributes : CFDictionary ) {
        
        var pixelBuffers =  [CVPixelBuffer]()
        
        while( true ) {
            
            var buffer : CVPixelBuffer? = nil
            
            let err : OSStatus = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, attributes, &buffer)
            
            if( err == kCVReturnWouldExceedAllocationThreshold ) {
                break
            }
            
            pixelBuffers.append(buffer!)
        }
        
        pixelBuffers.removeAll()
        
    }
    deinit {
        if(capturedImageTextureCache != nil) {
            CVMetalTextureCacheFlush(capturedImageTextureCache, 0);
        }
    }


}
