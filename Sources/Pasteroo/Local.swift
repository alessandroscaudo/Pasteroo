import SwiftUI

/// Drop-in replacement for `@State`, built on `@StateObject`.
/// SwiftUI's `@State` is a compiler macro on recent SDKs and its plugin ships
/// only with Xcode; this keeps the project buildable with the Command Line Tools.
@propertyWrapper
struct Local<Value>: DynamicProperty {
    private final class Box: ObservableObject {
        @Published var value: Value
        init(_ value: Value) { self.value = value }
    }

    @StateObject private var box: Box

    init(wrappedValue: Value) {
        _box = StateObject(wrappedValue: Box(wrappedValue))
    }

    var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    var projectedValue: Binding<Value> { $box.value }
}
