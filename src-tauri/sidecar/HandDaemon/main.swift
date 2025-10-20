import Foundation

let detectors: [GestureDetector] = [
    ByeDetector(
        minConfidence: 0.12,
        windowSec: 1.00,
        cooldownSec: 0.45,
        minDuration: 0.22,
        rMin: 0.09,
        rCvMax: 1.20,
        baseAlphaThr: 12.0,
        rRef: 0.11,
        omegaZeroThresh: 0.6,
        minZeroDt: 0.08,
        minZeroPairs: 1        
    )
]

let stream = HandStream(detectors: detectors)
stream.start()
RunLoop.main.run()
