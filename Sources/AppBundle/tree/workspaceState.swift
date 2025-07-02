import AppKit
import Foundation
import Common

private let workspaceStateFile = URL(filePath: "/tmp/\(aeroSpaceAppId)-workspace-state.json")

@MainActor
func saveWorldState() {
    let world = FrozenWorld(
        workspaces: Workspace.all.map { FrozenWorkspace($0) },
        monitors: monitors.map(FrozenMonitor.init)
    )
    guard let data = JSONEncoder.aeroSpaceDefault.encodeToString(world)?.data(using: .utf8) else { return }
    try? data.write(to: workspaceStateFile)
}

@MainActor
@discardableResult
func restoreWorldState() async -> Bool {
    guard let data = try? Data(contentsOf: workspaceStateFile) else { return false }
    guard let world = try? JSONDecoder().decode(FrozenWorld.self, from: data) else { return false }
    let monitors = monitors
    let topLeftCornerToMonitor = monitors.grouped { $0.rect.topLeftCorner }
    for frozenWorkspace in world.workspaces {
        let workspace = Workspace.get(byName: frozenWorkspace.name)
        _ = topLeftCornerToMonitor[frozenWorkspace.monitor.topLeftCorner]?
            .singleOrNil()?
            .setActiveWorkspace(workspace)
        for frozenWindow in frozenWorkspace.floatingWindows {
            MacWindow.get(byId: frozenWindow.id)?.bindAsFloatingWindow(to: workspace)
        }
        for frozenWindow in frozenWorkspace.macosUnconventionalWindows {
            MacWindow.get(byId: frozenWindow.id)?.bindAsFloatingWindow(to: workspace)
        }
        let prevRoot = workspace.rootTilingContainer
        let potentialOrphans = prevRoot.allLeafWindowsRecursive
        prevRoot.unbindFromParent()
        restoreTreeRecursiveAllowMissing(frozenContainer: frozenWorkspace.rootTilingNode, parent: workspace, index: INDEX_BIND_LAST)
        for window in (potentialOrphans - workspace.rootTilingContainer.allLeafWindowsRecursive) {
            try? await window.relayoutWindow(on: workspace, forceTile: true)
        }
    }
    for monitor in world.monitors {
        _ = topLeftCornerToMonitor[monitor.topLeftCorner]?
            .singleOrNil()?
            .setActiveWorkspace(Workspace.get(byName: monitor.visibleWorkspace))
    }
    return true
}

@MainActor
private func restoreTreeRecursiveAllowMissing(
    frozenContainer: FrozenContainer,
    parent: NonLeafTreeNodeObject,
    index: Int
) {
    let container = TilingContainer(
        parent: parent,
        adaptiveWeight: frozenContainer.weight,
        frozenContainer.orientation,
        frozenContainer.layout,
        index: index
    )

    for (i, child) in frozenContainer.children.enumerated() {
        switch child {
            case .window(let w):
                if let window = MacWindow.get(byId: w.id) {
                    window.bind(to: container, adaptiveWeight: w.weight, index: i)
                }
            case .container(let c):
                restoreTreeRecursiveAllowMissing(frozenContainer: c, parent: container, index: i)
        }
    }
}
