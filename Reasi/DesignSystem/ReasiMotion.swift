import SwiftUI

enum ReasiMotion {
    static let fastMilliseconds = 140
    static let baseMilliseconds = 220
    static let slowMilliseconds = 360

    static let fast = Animation.easeOut(duration: 0.14)
    static let base = Animation.easeInOut(duration: 0.22)
    static let slow = Animation.easeInOut(duration: 0.36)
    static let tactileSpring = Animation.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.04)
}

