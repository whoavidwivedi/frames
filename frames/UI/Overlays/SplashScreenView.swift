import SwiftUI

public struct SplashScreenView: View {
    public var onComplete: () -> Void

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        Color.clear.onAppear(perform: onComplete)
    }
}
