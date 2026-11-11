import AppKit
import SwiftUI
import Combine

/// Equivalente a `@State` sin macros.
///
/// En los SDK recientes de Apple `@State` es una macro cuyo plugin solo viene
/// con Xcode completo, así que con las herramientas de línea de comandos no
/// compila. Este envoltorio guarda el valor en un `@StateObject` (que no es
/// macro) y se usa igual: `@ViewState private var x = 0`, `$x` da un Binding.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    final class Storage: ObservableObject {
        @Published var value: Value
        init(_ value: Value) { self.value = value }
    }

    @StateObject private var storage: Storage

    init(wrappedValue: Value) {
        _storage = StateObject(wrappedValue: Storage(wrappedValue))
    }

    var wrappedValue: Value {
        get { storage.value }
        nonmutating set { storage.value = newValue }
    }

    var projectedValue: Binding<Value> {
        let storage = storage
        return Binding(get: { storage.value }, set: { storage.value = $0 })
    }
}
