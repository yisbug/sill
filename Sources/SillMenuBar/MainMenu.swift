import AppKit

/// The main menu of an app that never shows one. An accessory app (LSUIElement) has no menu bar,
/// but AppKit still routes key equivalents through the main menu, so without this ⌘C, ⌘A, ⌘F,
/// ⌘W and ⌘Q would do nothing in the Settings and Log windows.
enum MainMenu {
    @MainActor
    static func make() -> NSMenu {
        let main = NSMenu()

        let sill = submenu(in: main, title: String(localized: "Sill", comment: "主菜单：应用菜单名称"))
        sill.addItem(withTitle: String(localized: "About Sill", comment: "主菜单：关于应用"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        sill.addItem(.separator())
        sill.addItem(withTitle: String(localized: "Settings…", comment: "主菜单：打开设置"), action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        sill.addItem(.separator())
        sill.addItem(withTitle: String(localized: "Quit Sill", comment: "主菜单：退出应用"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let edit = submenu(in: main, title: String(localized: "Edit", comment: "主菜单：编辑菜单"))
        edit.addItem(withTitle: String(localized: "Undo", comment: "编辑菜单：撤销"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: String(localized: "Redo", comment: "编辑菜单：重做"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: String(localized: "Cut", comment: "编辑菜单：剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: String(localized: "Copy", comment: "编辑菜单：复制"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: String(localized: "Paste", comment: "编辑菜单：粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: String(localized: "Select All", comment: "编辑菜单：全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        let findItem = edit.addItem(withTitle: String(localized: "Find", comment: "编辑菜单：查找子菜单"), action: nil, keyEquivalent: "")
        let find = NSMenu(title: String(localized: "Find", comment: "编辑菜单：查找子菜单"))
        // performFindPanelAction: with the NSFindPanelAction tags, which a text view with a find
        // bar (the Log window) answers.
        let actions: [(String, String, NSFindPanelAction)] = [(String(localized: "Find…", comment: "查找菜单：打开查找栏"), "f", .showFindPanel),
                                                              (String(localized: "Find Next", comment: "查找菜单：下一处"), "g", .next),
                                                              (String(localized: "Find Previous", comment: "查找菜单：上一处"), "G", .previous)]
        for (title, key, tag) in actions {
            let item = find.addItem(withTitle: title, action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: key)
            item.tag = Int(tag.rawValue)
        }
        findItem.submenu = find

        let window = submenu(in: main, title: String(localized: "Window", comment: "主菜单：窗口菜单"))
        window.addItem(withTitle: String(localized: "Minimize", comment: "窗口菜单：最小化"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: String(localized: "Close", comment: "窗口菜单：关闭"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        return main
    }

    @MainActor
    private static func submenu(in main: NSMenu, title: String) -> NSMenu {
        let item = main.addItem(withTitle: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        return menu
    }
}
