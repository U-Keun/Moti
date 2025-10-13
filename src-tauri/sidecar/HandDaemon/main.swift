import Foundation
import AVFoundation
func printHelloJSON() {
    let s = "{\"type\":\"hello\"}\n"
    FileHandle.standardOutput.write(Data(s.utf8))
    fflush(stdout)
}
func requestCameraAndWait() {
    AVCaptureDevice.requestAccess(for: .video) { _ in
        CFRunLoopStop(CFRunLoopGetMain())
    }
}
printHelloJSON()
requestCameraAndWait()
CFRunLoopRun()
