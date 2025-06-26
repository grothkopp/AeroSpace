import AppKit
import Common

enum FrozenTreeNode: Codable, Sendable {
    case container(FrozenContainer)
    case window(FrozenWindow)

    private enum CodingKeys: String, CodingKey { case type, container, window }
    private enum NodeType: String, Codable { case container, window }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(NodeType.self, forKey: .type)
        switch type {
            case .container:
                let value = try container.decode(FrozenContainer.self, forKey: .container)
                self = .container(value)
            case .window:
                let value = try container.decode(FrozenWindow.self, forKey: .window)
                self = .window(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case .container(let value):
                try container.encode(NodeType.container, forKey: .type)
                try container.encode(value, forKey: .container)
            case .window(let value):
                try container.encode(NodeType.window, forKey: .type)
                try container.encode(value, forKey: .window)
        }
    }
}

struct FrozenContainer: Codable, Sendable {
    let children: [FrozenTreeNode]
    let layout: Layout
    let orientation: Orientation
    let weight: CGFloat

    @MainActor init(_ container: TilingContainer) {
        children = container.children.map {
            switch $0.nodeCases {
                case .window(let w): .window(FrozenWindow(w))
                case .tilingContainer(let c): .container(FrozenContainer(c))
                case .workspace,
                     .macosMinimizedWindowsContainer,
                     .macosHiddenAppsWindowsContainer,
                     .macosFullscreenWindowsContainer,
                     .macosPopupWindowsContainer:
                    illegalChildParentRelation(child: $0, parent: container)
            }
        }
        layout = container.layout
        orientation = container.orientation
        weight = getWeightOrNil(container) ?? 1
    }
}

struct FrozenWindow: Codable, Sendable {
    let id: UInt32
    let weight: CGFloat

    @MainActor init(_ window: Window) {
        id = window.windowId
        weight = getWeightOrNil(window) ?? 1
    }
}

@MainActor private func getWeightOrNil(_ node: TreeNode) -> CGFloat? {
    ((node.parent as? TilingContainer)?.orientation).map { node.getWeight($0) }
}
