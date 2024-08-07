//
//  CodeEditWindowController.swift
//  CodeEdit
//
//  Created by Pavel Kasila on 18.03.22.
//

import Cocoa
import SwiftUI
import Combine

final class CodeEditWindowController: NSWindowController, NSToolbarDelegate, ObservableObject {
    @Published var navigatorCollapsed = false
    @Published var inspectorCollapsed = false
    @Published var toolbarCollapsed = false

    var observers: [NSKeyValueObservation] = []

    var workspace: WorkspaceDocument?
    var workspaceSettings: CEWorkspaceSettings?
    var workspaceSettingsWindow: NSWindow?
    var quickOpenPanel: SearchPanel?
    var commandPalettePanel: SearchPanel?
    var navigatorSidebarViewModel: NavigatorSidebarViewModel?

    var taskNotificationHandler: TaskNotificationHandler

    var splitViewController: NSSplitViewController!

    internal var cancellables = [AnyCancellable]()

    init(
        window: NSWindow?,
        workspace: WorkspaceDocument?,
        taskNotificationHandler: TaskNotificationHandler
    ) {
        self.taskNotificationHandler = taskNotificationHandler
        super.init(window: window)
        guard let workspace else { return }
        self.workspace = workspace
        self.workspaceSettings = CEWorkspaceSettings(workspaceDocument: workspace)
        setupSplitView(with: workspace)

        // Previous:
        // An NSHostingController is used, so the root viewController of the window is a SwiftUI-managed one.
        // This allows us to use some SwiftUI features, like focusedSceneObject.
        // -----
        // let view = CodeEditSplitView(controller: splitViewController).ignoresSafeArea()
        // contentViewController = NSHostingController(rootView: view)
        // -----
        //
        // New:
        // The previous decision led to a very jank split controller mechanism because SwiftUI's layout system is not
        // very compatible with AppKit's when it comes to the inspector/navigator toolbar & split view system.
        // -----
        contentViewController = splitViewController
        // -----

        observers = [
            splitViewController.splitViewItems.first!.observe(\.isCollapsed, changeHandler: { [weak self] item, _ in
                self?.navigatorCollapsed = item.isCollapsed
            }),
            splitViewController.splitViewItems.last!.observe(\.isCollapsed, changeHandler: { [weak self] item, _ in
                self?.inspectorCollapsed = item.isCollapsed
            })
        ]

        setupToolbar()
        registerCommands()
    }

    deinit { cancellables.forEach({ $0.cancel() }) }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupSplitView(with workspace: WorkspaceDocument) {
        guard let window else {
            assertionFailure("No window found for this controller. Cannot set up content.")
            return
        }

        let navigatorModel = NavigatorSidebarViewModel()
        navigatorSidebarViewModel = navigatorModel
        self.splitViewController = CodeEditSplitViewController(
            workspace: workspace,
            navigatorViewModel: navigatorModel,
            windowRef: window
        )
        self.listenToDocumentEdited(workspace: workspace)
    }

    private func getSelectedCodeFile() -> CodeFileDocument? {
        workspace?.editorManager.activeEditor.selectedTab?.file.fileDocument
    }

    @IBAction func saveDocument(_ sender: Any) {
        guard let codeFile = getSelectedCodeFile() else { return }
        codeFile.save(sender)
        workspace?.editorManager.activeEditor.temporaryTab = nil
    }

    @IBAction func openCommandPalette(_ sender: Any) {
        if let workspace, let state = workspace.commandsPaletteState {
            if let commandPalettePanel {
                if commandPalettePanel.isKeyWindow {
                    commandPalettePanel.close()
                    state.reset()
                    return
                } else {
                    state.reset()
                    window?.addChildWindow(commandPalettePanel, ordered: .above)
                    commandPalettePanel.makeKeyAndOrderFront(self)
                }
            } else {
                let panel = SearchPanel()
                self.commandPalettePanel = panel
                let contentView = QuickActionsView(state: state, closePalette: panel.close)
                panel.contentView = NSHostingView(rootView: SettingsInjector { contentView })
                window?.addChildWindow(panel, ordered: .above)
                panel.makeKeyAndOrderFront(self)
            }
        }
    }

    @IBAction func openQuickly(_ sender: Any) {
        if let workspace, let state = workspace.openQuicklyViewModel {
            if let quickOpenPanel {
                if quickOpenPanel.isKeyWindow {
                    quickOpenPanel.close()
                    return
                } else {
                    window?.addChildWindow(quickOpenPanel, ordered: .above)
                    quickOpenPanel.makeKeyAndOrderFront(self)
                }
            } else {
                let panel = SearchPanel()
                self.quickOpenPanel = panel

                let contentView = OpenQuicklyView(state: state) {
                    panel.close()
                } openFile: { file in
                    workspace.editorManager.openTab(item: file)
                }.environmentObject(workspace)

                panel.contentView = NSHostingView(rootView: SettingsInjector { contentView })
                window?.addChildWindow(panel, ordered: .above)
                panel.makeKeyAndOrderFront(self)
            }
        }
    }

    @IBAction func closeCurrentTab(_ sender: Any) {
        if (workspace?.editorManager.activeEditor.tabs ?? []).isEmpty {
            self.closeActiveEditor(self)
        } else {
            workspace?.editorManager.activeEditor.closeSelectedTab()
        }
    }

    @IBAction func closeActiveEditor(_ sender: Any) {
        if workspace?.editorManager.editorLayout.findSomeEditor(except: workspace?.editorManager.activeEditor) == nil {
            NSApp.sendAction(#selector(NSWindow.close), to: nil, from: nil)
        } else {
            workspace?.editorManager.activeEditor.close()
        }
    }
}
