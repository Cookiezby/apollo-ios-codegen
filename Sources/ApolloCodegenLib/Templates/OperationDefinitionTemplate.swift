import IR
import GraphQLCompiler
import TemplateString
import OrderedCollections

/// Provides the format to convert a [GraphQL Operation](https://spec.graphql.org/draft/#sec-Language.Operations)
/// into Swift code.
struct OperationDefinitionTemplate: OperationTemplateRenderer {
  /// IR representation of source [GraphQL Operation](https://spec.graphql.org/draft/#sec-Language.Operations).
  let operation: IR.Operation

  let config: ApolloCodegen.ConfigurationContext

  let target: TemplateTarget = .operationFile

  var template: TemplateString {
    let definition = IR.Definition.operation(operation)

    return TemplateString(
    """
    \(OperationDeclaration())
      \(DocumentType.render(
        operation.definition,
        identifier: config.operationIdentifierFactory.identifier(for: operation),
        fragments: operation.referencedFragments,
        config: config,
        accessControlRenderer: { accessControlModifier(for: .member) }()
      ))

      \(section: VariableProperties(operation.definition.variables))

      \(Initializer(operation.definition.variables))

      \(section: VariableAccessors(operation.definition.variables))

      \(accessControlModifier(for: .member))struct Data: \(definition.renderedSelectionSetType(config)) {
        \(SelectionSetTemplate(
            definition: definition,
            generateInitializers: config.options.shouldGenerateSelectionSetInitializers(for: operation),
            config: config,
            renderAccessControl: { accessControlModifier(for: .member) }()
        ).renderBody())
      }
    }

    """)
  }

  private func OperationDeclaration() -> TemplateString {
    return """
    \(accessControlModifier(for: .parent))\
    \(classDefinitionKeywords) \(operation.generatedDefinitionName): \
    \(operation.definition.operationType.renderedProtocolName) {
      \(accessControlModifier(for: .member))\
    static let operationName: String = "\(operation.definition.name)"
    """
  }

  enum DocumentType {
    static func render(
      _ operation: CompilationResult.OperationDefinition,
      identifier: @autoclosure () -> String,
      fragments: OrderedSet<IR.NamedFragment>,
      config: ApolloCodegen.ConfigurationContext,
      accessControlRenderer: @autoclosure () -> String
    ) -> TemplateString {
      let includeFragments = !fragments.isEmpty
      let includeDefinition = config.options.operationDocumentFormat.contains(.definition)

      return TemplateString("""
      \(accessControlRenderer())\
      static let operationDocument: \(config.ApolloAPITargetName).OperationDocument = .init(
      \(if: config.options.operationDocumentFormat.contains(.operationId), """
        operationIdentifier: \"\(identifier())\"\(if: includeDefinition, ",")
      """)
      \(if: includeDefinition, """
        definition: .init(
          \(operation.source.formattedSource())\(if: includeFragments, ",")
          \(if: includeFragments,
                            "fragments: [\(fragments.map { "\($0.name.asFragmentName).self" }, separator: ", ")]")
        ))
      """,
      else: """
      )
      """)
      """
      )
    }
  }

}

fileprivate extension CompilationResult.OperationType {
  var renderedProtocolName: String {
    switch self {
    case .query: return "GraphQLQuery"
    case .mutation: return "GraphQLMutation"
    case .subscription: return "GraphQLSubscription"
    }
  }
}

fileprivate extension String {
  func formattedSource() -> Self {
    return "#\"\(convertedToSingleLine())\"#"
  }
}
