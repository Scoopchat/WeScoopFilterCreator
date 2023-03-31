/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 An `SCNNode` subclass demonstrating a basic use of `ARSCNFaceGeometry`.
 */
import Metal
import ARKit
import SceneKit
import CoreVideo
import MetalKit

class FaceMask: SCNNode, VirtualFaceContent {
    
    var info: MaskInfo?
    
    var worldNode : SCNNode?
    
    var faceNode : SCNNode?

    var needsEyeUpdate: Bool = false
    
    //later ... eye ...
    var device : MTLDevice
 
    var subdirectory : String?

    var baseGeometry : SCNGeometry?
    
    var needsCameraTexture: Bool = false
    
    var resetKalamanFilters : Bool = false
    
    var faceGeometry : ARSCNFaceGeometry
    
    lazy var blendShapeStates: [ARFaceAnchor.BlendShapeLocation: Float] = {
        
        var shapeStates: [ARFaceAnchor.BlendShapeLocation: Float] = [:]
        
        for shape in defaultBlendShapes {
            
            shapeStates[shape] = -1.0
            
        }
        
        return shapeStates
        
    }()
    
    lazy var textureLoader  : MTKTextureLoader = {
        return MTKTextureLoader(device:self.device)
    }()
 
    var lutTextures : [LUTType: MTLTexture?] = [:]

    var overlaySKScene : SKScene?

    var usesCameraTexture : Bool = false
    //tmp comment
lazy var colorParameters: ColorProcessingParameters = {
   
        return defaultColorProcessingParameters()
    }()
    
    

    init(named : String, subdirectory: String? = "Models.scnassets", device : MTLDevice) {
        
        
        self.device = device
        
        self.subdirectory = subdirectory
        
        faceGeometry = ARSCNFaceGeometry(device: device, fillMesh: false)!
        
        
        let sceneNode = loadSceneKitScene(named: named, subdirectory: subdirectory)!
        
        self.lutTextures = loadLookUpTables(node: sceneNode, subdirectory: subdirectory, device: device)

       
        
        worldNode = sceneNode.childNode(withName: "world", recursively: true)
        
        faceNode = sceneNode.childNode(withName: "face", recursively: true)
    
            
       if let faceGeometryNode = faceNode?.childNode(withName: "geometry", recursively: true) {
        
            baseGeometry = loadAlternateTextureCoordinates(geometry: faceGeometry)

            let materials = faceGeometryNode.geometry!.materials
        
            baseGeometry?.materials =  materials

            let firstMaterial = materials.first!
        
        
            let cameraTextureProperty = firstMaterial.value(forKeyPath: "cameraTexture") as? SCNMaterialProperty
        
            let displacementMapProperty = firstMaterial.value(forKeyPath: "displacementMap") as? SCNMaterialProperty

            if cameraTextureProperty != nil {
                
                print("found camera texture custom property")
                
                let placeholderTextureProperty = SCNMaterialProperty(contents: UIColor.clear)
                
                placeholderTextureProperty.mappingChannel = firstMaterial.diffuse.mappingChannel == 0 ? 1 : 0
                
                firstMaterial.setValue(placeholderTextureProperty, forKeyPath: "placeholderTexture")
                
                /*
                Use the opposite channel to store displacemnt
                */
                firstMaterial.setValue(firstMaterial.diffuse.mappingChannel == 0 ? 1 : 0, forKey: "displacementMappingChannel")
                
                var useDisplacement = false
                
                if displacementMapProperty == nil {
                    firstMaterial.setValue(nil, forKeyPath: "displacementMap")
                } else {
                    useDisplacement = true
                }
                
                print("useDisplacement: \(useDisplacement)")

                firstMaterial.setValue(useDisplacement ? 1 : 0, forKey: "useDisplacement")

                firstMaterial.setValue(1, forKey: "useLuma")

                var backgroundAverage : Float = defaultBackgroundAverage
                
                var backgroundInfluence : Float = defaultBackgroundInfluence
                
                if let currentBackgroundAverage = firstMaterial.value(forKeyPath: "backgroundAverage") as? Float {
                    backgroundAverage = currentBackgroundAverage
                }
                
                if let currentBackgroundInfluence = firstMaterial.value(forKeyPath: "backgroundInfluence") as? Float {
                    backgroundInfluence = currentBackgroundInfluence
                }
                
                firstMaterial.setValue(backgroundAverage, forKeyPath: "backgroundAverage")

                firstMaterial.setValue(backgroundInfluence, forKeyPath: "backgroundInfluence")
                
                print("backgroundAverage: \(backgroundAverage)")

                print("backgroundInfluence: \(backgroundInfluence)")

                if firstMaterial.shaderModifiers == nil {
                    firstMaterial.shaderModifiers = [:]
                }
                
                if firstMaterial.shaderModifiers?[SCNShaderModifierEntryPoint.fragment] == nil && !useDisplacement {
                    
                    print("use makeup fragment modifier")
                    
                    if let fragmentModifier = makeupFragmentModifierSource() {
                        firstMaterial.shaderModifiers?[SCNShaderModifierEntryPoint.fragment] = fragmentModifier
                    }
                    
                }
                
                if firstMaterial.shaderModifiers?[SCNShaderModifierEntryPoint.fragment] == nil && useDisplacement {

                    print("use displacement makeup fragment modifier")

                    if let fragmentModifier = displacementFragmentModifierSource() {
                        firstMaterial.shaderModifiers?[SCNShaderModifierEntryPoint.fragment] = fragmentModifier
                    }

                }
                
                if firstMaterial.shaderModifiers?[SCNShaderModifierEntryPoint.geometry] == nil && useDisplacement {
                    
                    print("use displacement geometry modifier")

                    if let geoemetryModifier = displacementGeometryModifierSource() {
                        firstMaterial.shaderModifiers?[SCNShaderModifierEntryPoint.geometry] = geoemetryModifier
                    }
                    
                }
                
                
                self.needsCameraTexture = true
                
            } else {
                self.needsCameraTexture = false
            }
        

            baseGeometry?.materials =  materials
        
        } else {
             baseGeometry = faceGeometry
        }
        
        

        let eyeMaterial = SCNMaterial()
        eyeMaterial.diffuse.contents = UIColor.clear
        eyeMaterial.writesToDepthBuffer = false
        eyeMaterial.readsFromDepthBuffer = true
        
        
        super.init()
        
        self.name = named
        self.geometry = baseGeometry

        if let cameraNode = sceneNode.childNode(withName: "camera", recursively: true) {
            
            if let camera = cameraNode.camera {
                //tmp comment
                 colorParameters.saturationIntensity = Float(camera.saturation)
                colorParameters.contrastIntensity = Float(camera.contrast)
            }
        }
        
        worldNode?.enumerateChildNodes { (node, _) in
            
            
            if node.name == "overlay" && node.childNodes.count > 0 {
                
                node.isHidden = true
                
                let overlayNode = node.childNodes[0]
                
                if let skScene = createOverlaySKSceneFromNode(node: overlayNode, subdirectory: subdirectory) {
                    self.overlaySKScene = skScene
                    
                }
            }
            
            
            // MARK: World Lights and Constraints
            
            if node.light != nil && node.constraints != nil {
                
                for constraint in node.constraints! {
                    
                    if let lookAt = constraint as? SCNLookAtConstraint {
                        lookAt.target = self
                    }
                }
                
            }
            
            
        }
        
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("\(#function) has not been implemented")
    }
    
   
    func loadSpecialMaterials() {
        
        if faceNode != nil {
            loadSpecialMaterialsForHierarchy(node: faceNode!, subdirectory: subdirectory)
        }
        
        print("done loading specials")
        
    }
     // MARK: State
    
    func setTracking( isTracking: Bool ) {
        
        if isTracking {
            if( opacity == 0.0 )  {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.3
                self.opacity = 1.0
                
                
                
                SCNTransaction.commit()
            }
        }
        else {
            if( opacity == 1.0 )
            {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.3
                self.opacity = 0.0
                
                
                SCNTransaction.commit()
            }
        }
    }
    
    
    
    // MARK: Updates
    
    func updateFaceAnchor(withFaceAnchor anchor: ARFaceAnchor) {
        
        //let faceGeometry = faceGeometry
      
        faceGeometry.update(from: anchor.geometry)
        
        if blendShapeStates.count > 0 {
            processBlendShapes(blendShapes: anchor.blendShapes)
        }
    }
    
    func updateCameraTexture(withCameraTexture texture: MTLTexture) {
 
        
        guard let material = geometry?.materials.first else { return }
        
        if material.value(forKey: "cameraTexture") != nil {
            let cameraTextureProperty = material.value(forKey: "cameraTexture") as! SCNMaterialProperty

            cameraTextureProperty.contents = texture
        }
    }
    
    
    func updateEyeGeometry( eyeScale: Float, leftEyeCenter: vector_float3, leftEyeGaze: vector_float3, rightEyeCenter: vector_float3, rightEyeGaze: vector_float3, xScale: Float ) {

        //tmp comment
        let scale =   0.46080 * self.simdPosition.z + 0.303
        
        var leftXY = float2(x:leftEyeCenter.x ,y:leftEyeCenter.y )
        var rightXY = float2(x:rightEyeCenter.x ,y:rightEyeCenter.y )
        
        
       /* if eyeKalmanFilters == nil {
            eyeKalmanFilters =  [Eye.left: HCKalmanAlgorithm(initialLocation: leftXY ), Eye.right: HCKalmanAlgorithm(initialLocation: rightXY )]
            
        } else {
            
            if(resetKalamanFilters) {
                eyeKalmanFilters![Eye.left]!.resetKalman(newStartLocation: leftXY)
                eyeKalmanFilters![Eye.right]!.resetKalman(newStartLocation: rightXY)
                resetKalamanFilters = false
            } else {
               leftXY = eyeKalmanFilters![Eye.left]!.processState(currentLocation: &leftXY)
               rightXY = eyeKalmanFilters![Eye.right]!.processState(currentLocation: &rightXY)
            }
        }*/
        
        
        
    }
    
   
    func processBlendShapes( blendShapes: [ARFaceAnchor.BlendShapeLocation: Any] ) {
        
        for( location  ) in blendShapeStates.keys {
            
            if let value = blendShapes[location] as! Float? {
                blendShapeStates[location] = value
            }
            
        }
        
    }
    
    func mouthOpenness() -> Float {
        
        guard let value = blendShapeStates[ARFaceAnchor.BlendShapeLocation.jawOpen] else {
            return -1.0
        }
        
        return value
        
    }
    
    override func removeFromParentNode() {
        
        super.removeFromParentNode()
        
        
    }
    
    deinit {
        
        
       
        
    }
}


