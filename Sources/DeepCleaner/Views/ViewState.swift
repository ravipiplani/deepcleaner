import SwiftUI

/// The macOS 27 SDK declares `@State` as a macro whose plugin ships only with Xcode, so builds with
/// the Command Line Tools fail. Referring to the underlying property wrapper through a typealias
/// sidesteps the macro and works under both toolchains.
typealias ViewState<Value> = SwiftUI.State<Value>
