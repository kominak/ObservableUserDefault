import SwiftCompilerPlugin
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct ObservableUserDefaultPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ObservableUserDefaultMacro.self
    ]
}

public struct ObservableUserDefaultMacro: AccessorMacro {
    
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        // Ensure the macro can only be attached to variable properties.
        guard let varDecl = declaration.as(VariableDeclSyntax.self), varDecl.bindingSpecifier.tokenKind == .keyword(.var) else {
            throw ObservableUserDefaultError.notVariableProperty
        }

        // Ensure the variable is defines a single property declaration, for example,
        // `var name: String` and not multiple declarations such as `var name, address: String`.
        guard varDecl.bindings.count == 1,
            let binding = varDecl.bindings.first
        else {
            throw ObservableUserDefaultError.propertyMustContainOnlyOneBinding
        }
        
        // Ensure there is no computed property block attached to the variable already.
        guard binding.accessorBlock == nil else {
            throw ObservableUserDefaultError.propertyMustHaveNoAccessorBlock
        }

        let defaultValue = binding.initializer

        // For simple variable declarations, the binding pattern is `IdentifierPatternSyntax`,
        // which defines the name of a single variable.
        guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier else {
            throw ObservableUserDefaultError.propertyMustUseSimplePatternSyntax
        }

        let supportedTypes = ["String", "Int", "Bool", "NSDate", "Data", "NSNumber"]
        let baseType: TypeSyntax
        let defaultValueString: String

        if let type = binding.typeAnnotation?.type.trimmed.as(OptionalTypeSyntax.self) {
            guard defaultValue == nil else {
                throw ObservableUserDefaultArgumentError.optionalTypeShouldHaveNoDefaultValue
            }

            baseType = type.wrappedType
            defaultValueString = "nil"
        }
        else if let type = binding.typeAnnotation?.type {

            guard let defaultValueExpr = defaultValue?.value else {
                throw ObservableUserDefaultArgumentError.nonOptionalTypeMustHaveDefaultValue
            }

            baseType = type
            defaultValueString = defaultValueExpr.description
        }
        else {
            throw ObservableUserDefaultArgumentError.unableToExtractRequiredValuesFromArgument
        }

        let typeDescription = baseType.description.trimmingCharacters(in: .whitespacesAndNewlines)

        // Direct storage
        if supportedTypes.contains(typeDescription) {
            return [
                #"""
                get {
                    access(keyPath: \.\#(pattern))
                    return UserDefaults.standard.value(forKey: "\#(pattern)") as? \#(baseType) ?? \#(raw: defaultValueString)
                }
                """#,
                #"""
                set {
                    withMutation(keyPath: \.\#(pattern)) {
                        UserDefaults.standard.set(newValue, forKey: "\#(pattern)")
                    }
                }
                """#
            ]
        }
        // Store as JSON Data
        else {
            return [
                #"""
                get {
                    access(keyPath: \.\#(pattern))
                
                    if let T = (\#(baseType).self as Any.Type) as? any RawRepresentable<String>.Type,
                        let value = UserDefaults.standard.value(forKey: "\#(pattern)") as? String,
                        let enumCase = T.init(rawValue: value)
                    {
                        return ((enumCase as Any) as? \#(baseType)) ?? \#(raw: defaultValueString)
                    }
                    else if let T = (\#(baseType).self as Any.Type) as? any RawRepresentable<Int>.Type,
                        let value = UserDefaults.standard.value(forKey: "\#(pattern)") as? Int,
                        let enumCase = T.init(rawValue: value)
                    {
                        return ((enumCase as Any) as? \#(baseType)) ?? \#(raw: defaultValueString)
                    }
                    else if let data = UserDefaults.standard.value(forKey: "\#(pattern)") as? Data,
                        let value = try? JSONDecoder().decode(\#(baseType).self, from: data)
                    {
                        return value
                    }
                    else {
                        return \#(raw: defaultValueString)
                    }
                }
                """#,
                #"""
                set {
                    withMutation(keyPath: \.\#(pattern)) {
                        if let enumCase = (newValue as Any) as? any RawRepresentable<String> {
                            UserDefaults.standard.set(enumCase.rawValue, forKey: "\#(pattern)")
                        }
                        else if let enumCase = (newValue as Any) as? any RawRepresentable<Int> {
                            UserDefaults.standard.set(enumCase.rawValue, forKey: "\#(pattern)")
                        }
                        else {
                            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "\#(pattern)")
                        }
                    }
                }
                """#
            ]
        }
    }
}

enum ObservableUserDefaultError: Error, CustomStringConvertible {
    case notVariableProperty
    case propertyMustContainOnlyOneBinding
    case propertyMustHaveNoAccessorBlock
    case propertyMustHaveNoInitializer
    case propertyMustUseSimplePatternSyntax
    
    var description: String {
        switch self {
        case .notVariableProperty:
            return "'@ObservableUserDefault' can only be applied to variables"
        case .propertyMustContainOnlyOneBinding:
            return "'@ObservableUserDefault' cannot be applied to multiple variable bindings"
        case .propertyMustHaveNoAccessorBlock:
            return "'@ObservableUserDefault' cannot be applied to computed properties"
        case .propertyMustHaveNoInitializer:
            return "'@ObservableUserDefault' cannot be applied to stored properties"
        case .propertyMustUseSimplePatternSyntax:
            return "'@ObservableUserDefault' can only be applied to a variables using simple declaration syntax, for example, 'var name: String'"
        }
    }
}

enum ObservableUserDefaultArgumentError: Error, CustomStringConvertible {
    case macroShouldOnlyContainOneArgument
    case nonOptionalTypeMustHaveDefaultValue
    case optionalTypeShouldHaveNoDefaultValue
    case unableToExtractRequiredValuesFromArgument
    
    var description: String {
        switch self {
        case .macroShouldOnlyContainOneArgument:
            return "Must provide an argument when using '@ObservableUserDefault' with parentheses"
        case .nonOptionalTypeMustHaveDefaultValue:
            return "'@ObservableUserDefault' arguments on non-optional types must provide default values"
        case .optionalTypeShouldHaveNoDefaultValue:
            return "'@ObservableUserDefault' arguments on optional types should not use default values"
        case .unableToExtractRequiredValuesFromArgument:
            return "'@ObservableUserDefault' unable to extract the required values from the argument"
        }
    }
}
