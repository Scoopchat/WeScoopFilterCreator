
import Foundation
import CoreVideo
import CoreMedia

protocol RenderPixelBufferConsumer {
    func renderedOutput( didRender: CVPixelBuffer, atTime: CMTime )
    var renderCallbackQueue: DispatchQueue { get }
}


