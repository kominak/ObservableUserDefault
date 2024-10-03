import Foundation

@attached(accessor, names: named(get), named(set))
public macro ObservableUserDefault() = #externalMacro(
    module: "ObservableUserDefaultMacros",
    type: "ObservableUserDefaultMacro"
)
