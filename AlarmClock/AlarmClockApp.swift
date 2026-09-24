import SwiftUI

@main
struct AlarmClockApp: App {
    var body: some Scene {
        WindowGroup {
            // Replaced with the real root once store/UI/engine land.
            Text("Alarm")
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
        }
    }
}
