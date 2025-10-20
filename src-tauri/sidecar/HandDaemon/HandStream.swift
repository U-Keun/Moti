import Foundation
import AVFoundation
import Vision

final class HandStream: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let q = DispatchQueue(label: "hand.stream.q")
    private let handler = VNSequenceRequestHandler()
    private let req = VNDetectHumanHandPoseRequest()
    
    private var lastEmit = CFAbsoluteTimeGetCurrent()
    private var fpsEMA: Double = 0
    private var roi: CGRect? = nil

    private let detectors: [GestureDetector]

    private let emitLandmarks = false

    private var lastObsTime: CFAbsoluteTime = 0
    private let missGraceSec: CFAbsoluteTime = 0.5

    init(detectors: [GestureDetector]) {
        self.detectors = detectors
        super.init()
    }

    func start() {
        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        let cam: AVCaptureDevice?

        if #available(macOS 14.0, *) {
            // ✅ 14+ : ContinuityCamera 우선, 실패 시 내장 광각
            // (externalUnknown은 절대 넣지 않음)
            if let cc = AVCaptureDevice.default(.continuityCamera, for: .video, position: .unspecified) {
                cam = cc
            } else {
                let discovery = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.builtInWideAngleCamera],
                    mediaType: .video,
                    position: .unspecified
                )
                cam = discovery.devices.first
            }
        } else {
            // ✅ 13 이하 : Continuity 타입이 없으므로 기존 방식 유지
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
                mediaType: .video,
                position: .unspecified
            )
            cam = discovery.devices.first
        }

        guard let cam, let input = try? AVCaptureDeviceInput(device: cam) else {
            session.commitConfiguration()
            return
        }
        if session.canAddInput(input) { session.addInput(input) }

        let out = AVCaptureVideoDataOutput()
        out.alwaysDiscardsLateVideoFrames = true
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        out.setSampleBufferDelegate(self, queue: q)
        if session.canAddOutput(out) { session.addOutput(out) }

        if let c = out.connection(with: .video) {
            if #available(macOS 14.0, *) {
                if c.isVideoRotationAngleSupported(90) {
                    c.videoRotationAngle = 90
                }
            } else if c.isVideoOrientationSupported {
                c.videoOrientation = .portrait
            }
        }

        session.commitConfiguration()
        session.startRunning()

        req.maximumHandCount = 1
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        autoreleasepool {
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastEmit < 0.066 { return }

            guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            req.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)

            let orient: CGImagePropertyOrientation = {
                if #available(macOS 14.0, *),
                   connection.isVideoRotationAngleSupported(90),
                   connection.videoRotationAngle == 90 { return .right }
                else if connection.isVideoOrientationSupported,
                        connection.videoOrientation == .portrait { return .right }
                else { return .up }
            }()

            do {
                try handler.perform([req], on: pb, orientation: orient)
                guard let obs = req.results?.first else {
                    if now - lastObsTime > missGraceSec {
                        detectors.forEach { $0.reset() }
                        roi = nil
                    }
                    return
                }
                lastObsTime = now

                let all: [VNHumanHandPoseObservation.JointName] = [
                    .wrist,
                    .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
                    .indexMCP, .indexPIP, .indexDIP, .indexTip,
                    .middleMCP, .middlePIP, .middleDIP, .middleTip,
                    .ringMCP, .ringPIP, .ringDIP, .ringTip,
                    .littleMCP, .littlePIP, .littleDIP, .littleTip
                ]

                let ptsVN = all.compactMap { try? obs.recognizedPoint($0) }
                let n = max(1, ptsVN.count) // 분모 0 방지
                let conf = ptsVN.reduce(0.0) { $0 + Double($1.confidence) } / Double(n)

                let goodPts = ptsVN.filter { $0.confidence >= 0.3 }
                if !goodPts.isEmpty {
                    let xs = goodPts.map { CGFloat($0.location.x) }
                    let ys = goodPts.map { CGFloat($0.location.y) }
                    var box = CGRect(x: xs.min()!, y: ys.min()!,
                                    width: xs.max()! - xs.min()!,
                                    height: ys.max()! - ys.min()!)
                    let pad: CGFloat = 0.08
                    box = box.insetBy(dx: -pad, dy: -pad)
                    let minWH: CGFloat = 0.18
                    if box.width  < minWH { box.size.width  = minWH }
                    if box.height < minWH { box.size.height = minWH }

                    if let prev = roi {
                        let a: CGFloat = 0.35 // 0~1 (클수록 빠르게 따라감)
                        let ix = prev.origin.x  * (1 - a) + box.origin.x  * a
                        let iy = prev.origin.y  * (1 - a) + box.origin.y  * a
                        let iw = prev.size.width * (1 - a) + box.size.width * a
                        let ih = prev.size.height*(1 - a) + box.size.height*a
                        roi = CGRect(x: ix, y: iy, width: iw, height: ih)
                    } else {
                        roi = box
                    }
                }

                let dt = now - lastEmit
                let inst = 1.0 / dt
                fpsEMA = (fpsEMA == 0) ? inst : (0.2 * inst + 0.8 * fpsEMA)

                let pts = ptsVN.map { p -> [Double] in
                    [Double(p.location.x), Double(1 - p.location.y)]
                }

                if emitLandmarks {
                    emitLM(fps: fpsEMA, pts: pts, conf: conf)
                }

                for det in detectors {
                    if let payload = det.process(observation: obs, now: now) {
                        emitJSON(payload)
                    }
                }
                lastEmit = now
            } catch {
                roi = nil
                let now2 = CFAbsoluteTimeGetCurrent()
                if now2 - lastObsTime > missGraceSec {
                    detectors.forEach { $0.reset() }
                }
            }
        }
    }

    private func emitLM(fps: Double, pts: [[Double]], conf: Double) {
        emitJSON([
            "type": "lm",
            "t": Int(Date().timeIntervalSince1970 * 1000),
            "fps": Double((fps * 10).rounded() / 10),
            "hand": "unknown",
            "lm": pts,
            "conf": conf
        ])
    }

    private func emitJSON(_ dict: [String: Any]) {
        var d = dict
        if d["t"] == nil { d["t"] = Int(Date().timeIntervalSince1970 * 1000) }
        if let data = try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys]),
            let line = String(data: data, encoding: .utf8) { 
                print(line) 
                fflush(__stdoutp)
            }
    }
}

