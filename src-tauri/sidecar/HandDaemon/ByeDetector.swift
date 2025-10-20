import Foundation
import Vision
import CoreGraphics
import Darwin

/// 간단화: 가속도 RMS + 제로크로싱(히스테리시스) + 반경 적응 임계
final class ByeDetector: GestureDetector {
    let name = "bye_accel"

    // ===== Tunables =====
    private let minConfidence: Float         // 랜드마크 최소 신뢰도
    private let windowSec: CFAbsoluteTime    // 통계 윈도
    private let cooldownSec: CFAbsoluteTime  // EMIT 후 쿨다운
    private let minDuration: CFAbsoluteTime  // 최소 동작 시간
    private let rMin: CGFloat                // 최소 반경(손목-손가락 무게중심)
    private let rCvMax: CGFloat              // 반경 변동 계수 상한
    private let baseAlphaThr: CGFloat        // 기준 가속도(RMS) 임계
    private let rRef: CGFloat                // 반경 기준값(적응 스케일링)
    private let scaleMin: CGFloat = 0.6
    private let scaleMax: CGFloat = 1.8

    // 제로크로싱(ω) — 바이어스 제거 + 히스테리시스
    private let omegaBiasTau: CFAbsoluteTime = 0.35
    private let omegaZeroThresh: CGFloat     // e.g. 1.5 ~ 2.0 (rad/s)
    private let minZeroDt: CFAbsoluteTime    // 제로 간 최소 시간
    private let minZeroPairs: Int            // 최소 왕복 수(=교차쌍)

    // ===== State =====
    private enum GState { case idle, tracking, cooldown }
    private var state: GState = .idle
    private var cooldownUntil: CFAbsoluteTime = 0

    private struct Sample {
        let t: CFAbsoluteTime
        let theta: CGFloat   // 언랩된 각
        let r: CGFloat       // 반경
        let omega: CGFloat   // dθ/dt
        let alpha: CGFloat   // dω/dt
    }
    private var hist: [Sample] = []
    private var lastTheta: CGFloat? = nil
    private var lastOmega: CGFloat? = nil
    private var lastT: CFAbsoluteTime? = nil

    private var omegaBias: CGFloat = 0
    private var omegaZeroTimes: [CFAbsoluteTime] = []
    private var lastZeroTime: CFAbsoluteTime = 0

    private var trackingStart: CFAbsoluteTime? = nil

    // Debug
    private let DEBUG = (ProcessInfo.processInfo.environment["DEBUG_BYE"] == "1")
    @inline(__always) private func dbg(_ s: String) {
        guard DEBUG else { return }
        fputs("[bye_accel] \(s)\n", stderr); fflush(__stderrp)
    }

    init(
        minConfidence: Float = 0.18,
        windowSec: CFAbsoluteTime = 1.0,
        cooldownSec: CFAbsoluteTime = 0.40,
        minDuration: CFAbsoluteTime = 0.28,
        rMin: CGFloat = 0.14,
        rCvMax: CGFloat = 0.50,
        baseAlphaThr: CGFloat = 18.0,
        rRef: CGFloat = 0.22,
        omegaZeroThresh: CGFloat = 1.8,
        minZeroDt: CFAbsoluteTime = 0.14,
        minZeroPairs: Int = 1
    ) {
        self.minConfidence = minConfidence
        self.windowSec = windowSec
        self.cooldownSec = cooldownSec
        self.minDuration = minDuration
        self.rMin = rMin
        self.rCvMax = rCvMax
        self.baseAlphaThr = baseAlphaThr
        self.rRef = rRef
        self.omegaZeroThresh = omegaZeroThresh
        self.minZeroDt = minZeroDt
        self.minZeroPairs = minZeroPairs
    }

    func reset() {
        if case .cooldown = state { return }
        state = .idle
        cooldownUntil = 0
        hist.removeAll(keepingCapacity: true)
        omegaZeroTimes.removeAll(keepingCapacity: true)
        lastTheta = nil
        lastOmega = nil
        lastT = nil
        omegaBias = 0
        trackingStart = nil
    }

    func process(observation obs: VNHumanHandPoseObservation, now: CFAbsoluteTime) -> [String : Any]? {
        if now < cooldownUntil { return nil }

        // ===== 1) 필요한 랜드마크 =====
        guard let wrist = try? obs.recognizedPoint(.wrist), wrist.confidence >= minConfidence else {
            dbg("miss wrist"); return nil
        }
        // PIP 3개 중 >= 2개
        var pips: [VNRecognizedPoint] = []
        if let p = try? obs.recognizedPoint(.indexPIP),  p.confidence  >= minConfidence { pips.append(p) }
        if let p = try? obs.recognizedPoint(.middlePIP), p.confidence  >= minConfidence { pips.append(p) }
        if let p = try? obs.recognizedPoint(.ringPIP),   p.confidence  >= minConfidence { pips.append(p) }
        guard pips.count >= 2 else { dbg("miss PIP (<2)"); return nil }

        // 무게중심(평균)
        let cx = pips.reduce(0.0) { $0 + Double($1.location.x) } / Double(pips.count)
        let cy = pips.reduce(0.0) { $0 + Double($1.location.y) } / Double(pips.count)

        // wrist -> center 벡터 (Vision 좌표계: (0,0) 왼쪽하단, y↑)
        let vx = CGFloat(cx) - CGFloat(wrist.location.x)
        let vy = CGFloat(cy) - CGFloat(wrist.location.y)
        let r  = sqrt(vx*vx + vy*vy)
        var th = atan2(vy, vx) // [-π, π]

        // 언랩(이전 θ와 π 경계 최소화)
        if let tp = lastTheta {
            let twoPi = CGFloat.pi * 2
            let d = th - tp
            if d >  CGFloat.pi { th -= twoPi }
            if d < -CGFloat.pi { th += twoPi }
        }

        // 시간차
        let tPrev = lastT ?? now
        let dt = max(1e-3, now - tPrev)

        // 미분
        let omega: CGFloat
        if let tp = lastTheta {
            omega = (th - tp) / CGFloat(dt)
        } else {
            omega = 0
        }
        let alpha: CGFloat
        if let op = lastOmega {
            alpha = (omega - op) / CGFloat(dt)
        } else {
            alpha = 0
        }

        // 상태 업데이트
        lastTheta = th
        lastOmega = omega
        lastT = now

        // 기록/트림
        hist.append(.init(t: now, theta: th, r: r, omega: omega, alpha: alpha))
        trim(now)

        if trackingStart == nil { trackingStart = now }
        let dur = now - (trackingStart ?? now)

        // ===== 2) 제로크로싱: ω 바이어스 제거 + 히스테리시스 =====
        // 느린 바이어스 EMA
        let aBias = emaCoeff(omegaBiasTau, dt)
        omegaBias = omegaBias + aBias * (omega - omegaBias)

        // 교차 감지
        if hist.count >= 2 {
            let p  = hist[hist.count-2].omega - omegaBias
            let q  = omega - omegaBias
            let ps = (p >  omegaZeroThresh) ? 1 : (p < -omegaZeroThresh ? -1 : 0)
            let qs = (q >  omegaZeroThresh) ? 1 : (q < -omegaZeroThresh ? -1 : 0)
            if ps != 0, qs != 0, ps != qs, now - lastZeroTime >= minZeroDt {
                omegaZeroTimes.append(now)
                lastZeroTime = now
                let cut = now - windowSec
                while let f = omegaZeroTimes.first, f < cut { omegaZeroTimes.removeFirst() }
            }
        }
        let zeroPairs = max(0, omegaZeroTimes.count - 1) / 2

        // ===== 3) 윈도 통계 =====
        // r 평균/표준편차/변동계수
        var rSum: CGFloat = 0, rSq: CGFloat = 0
        for s in hist { rSum += s.r; rSq += s.r * s.r }
        let n = CGFloat(max(1, hist.count))
        let rMean = rSum / n
        let rVar  = max(0, rSq / n - rMean * rMean)
        let rStd  = sqrt(rVar)
        let rCv   = (rMean > 1e-6) ? (rStd / rMean) : 0

        // 가속도 RMS
        var aSq: CGFloat = 0
        for s in hist { aSq += s.alpha * s.alpha }
        let aRMS = sqrt(aSq / n)

        // 반경 적응형 에너지 임계
        let scale = max(scaleMin, min(scaleMax, rRef / max(0.12, rMean)))
        let alphaThr = baseAlphaThr * scale

        // ===== 4) 판정 =====
        let energyOK = (aRMS >= alphaThr)
        let rhythmOK = (zeroPairs >= minZeroPairs)
        let radiusOK = (rMean >= rMin && rCv <= rCvMax)
        let durOK    = (dur >= minDuration)

        if DEBUG {
            let msg = String(
                format: "ω=%5.3f α=%6.3f | aRMS=%5.3f thr=%5.3f | zeros=%d | r=%4.3f cv=%4.2f | dur=%4.2fs",
                Double(omega), Double(alpha), Double(aRMS), Double(alphaThr),
                zeroPairs, Double(rMean), Double(rCv), Double(dur)
            )
            dbg(msg)
        }

        switch state {
        case .idle:
            state = .tracking
            return nil
        case .tracking:
            if energyOK && rhythmOK && radiusOK && durOK {
                state = .cooldown
                cooldownUntil = now + cooldownSec
                prepareForNext(now)

                // 간단 confidence: 에너지/반경/rhythm 결합(0.0~1.0)
                let cE = min(1.0, Double(aRMS/alphaThr))
                let cR = max(0.0, 1.0 - Double((rCv / max(1e-6, rCvMax)) - 1.0))
                let cZ = min(1.0, Double(zeroPairs) / Double(max(minZeroPairs, 1)))
                let conf = max(0.0, min(1.0, 0.5*cE + 0.3*cZ + 0.2*cR))

                dbg(String(format:"EMIT conf=%.2f", conf))
                return [
                    "type": "gesture",
                    "name": name,
                    "conf": conf,
                    "r_mean": Double(rMean),
                    "r_cv": Double(rCv),
                    "zero_pairs": zeroPairs,
                    "alpha_rms": Double(aRMS)
                ]
            }
            return nil
        case .cooldown:
            if now >= cooldownUntil {
                state = .idle
                prepareForNext(now)
            }
            return nil
        }
    }

    // ===== Helpers =====
    private func trim(_ now: CFAbsoluteTime) {
        let cut = now - windowSec
        while let f = hist.first, f.t < cut { hist.removeFirst() }
    }
    private func emaCoeff(_ tau: CFAbsoluteTime, _ dt: CFAbsoluteTime) -> CGFloat {
        let a = 1.0 - exp(-dt / max(1e-3, tau))
        return CGFloat(min(1.0, max(0.0, a)))
    }

    private func prepareForNext(_ now: CFAbsoluteTime) {
        hist.removeAll(keepingCapacity: true)
        omegaZeroTimes.removeAll(keepingCapacity: true)
        lastTheta = nil
        lastOmega = nil
        lastT = nil
        omegaBias = 0
        trackingStart = nil
        lastZeroTime = 0
    }
}
