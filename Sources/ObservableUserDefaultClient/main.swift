import SwiftUI
import ObservableUserDefault

@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, macCatalyst 17.0, visionOS 1.0, *)
@Observable final class Person {

    @ObservableUserDefault
    @ObservationIgnored
    var address: String = "Test"
}

if #available(iOS 17.0, *) {

}
