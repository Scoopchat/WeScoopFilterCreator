//
//  ViewController.swift
//  WeScoopFilterCreator
//
//  Created by Dorian on 29.03.2023.
//

import UIKit
import Metal
import MetalKit
import ARKit

extension MTKView : RenderDestinationProvider {
}

class ViewController: UIViewController, MTKViewDelegate, ARSessionDelegate {
    
    var session: ARSession!
    var renderer: Renderer!
    //..inject from ARMetal project
    //var maskRecords = [MaskInfo]()
    var device: MTLDevice!
    var scene: SCNScene!
    var currentFaceNodeName: String?
    var isRecording: Bool = false
    //var assetWriter : RenderedVideoWriter?
    //.. end inject
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        session = ARSession()
        session.delegate = self
        scene = SCNScene()
        //.... inject
        //Utilities.clearCacheDirectory()

        // Set the view to use the default device
        if let mtkView = self.view as? MTKView {
            mtkView.device = MTLCreateSystemDefaultDevice()
            mtkView.backgroundColor = UIColor.clear
            mtkView.delegate = self
            
            guard mtkView.device != nil else {
                print("Metal is not supported on this device")
                return
            }
            self.device = mtkView.device!
            // Configure the renderer to draw to the view
            //renderer = Renderer(session: session, metalDevice: view.device!, renderDestination: view)
            renderer = Renderer(session: session, metalDevice: mtkView.device!, renderDestination: mtkView, sceneKitScene: scene)

            renderer.drawRectResized(size: view.bounds.size)
        }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(ViewController.handleTap(gestureRecognize:)))
        view.addGestureRecognizer(tapGesture)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
       // let configuration = ARWorldTrackingConfiguration()
        // Run the view's session
       // session.run(configuration)
        guard ARFaceTrackingConfiguration.isSupported else { return }
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        configuration.providesAudioData = true
        configuration.worldAlignment = .gravity
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])


    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        session.pause()
    }
    
    @objc
    func handleTap(gestureRecognize: UITapGestureRecognizer) {
        // Create anchor using the camera's current position
        if let currentFrame = session.currentFrame {
            
            // Create a transform with a translation of 0.2 meters in front of the camera
            var translation = matrix_identity_float4x4
            translation.columns.3.z = -0.2
            let transform = simd_mul(currentFrame.camera.transform, translation)
            
            // Add a new anchor to the session
            let anchor = ARAnchor(transform: transform)
            session.add(anchor: anchor)
        }
    }
    
    // MARK: - MTKViewDelegate
    
    // Called whenever view changes orientation or layout is changed
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer.drawRectResized(size: size)
    }
    
    // Called whenever the view needs to render
    func draw(in view: MTKView) {
        renderer.update()
    }
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        
    }
}
