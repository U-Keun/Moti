import Foundation
import Vision

protocol GestureDetector {
    var name: String { get }
    func reset()
    func process(observation: VNHumanHandPoseObservation,
        now: CFAbsoluteTime) -> [String: Any]?
}
