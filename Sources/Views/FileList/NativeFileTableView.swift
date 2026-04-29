import AppKit
import SwiftUI

// MARK: - Constants

private enum TableLayout {
    static let rowHeight: CGFloat = 24
    static let iconSize: CGFloat = 18
    static let cellPadding: CGFloat = 2
    static let iconTextSpacing: CGFloat = 6
    static let nameColumnMinWidth: CGFloat = 200
    static let nameColumnWidth: CGFloat = 350
    static let dateColumnMinWidth: CGFloat = 120
    static let dateColumnWidth: CGFloat = 160
    static let sizeColumnMinWidth: CGFloat = 60
    static let sizeColumnWidth: CGFloat = 80
}

private enum ColumnID {
    static let name = NSUserInterfaceItemIdentifier("name")
    static let dateModified = NSUserInterfaceItemIdentifier("dateModified")
    static let size = NSUserInterfaceItemIdentifier("size")
}

private enum CellID {
    static let name = NSUserInterfaceItemIdentifier("NameCell")
    static let date = NSUserInterfaceItemIdentifier("DateCell")
    static let size = NSUserInterfaceItemIdentifier("SizeCell")
}

// MARK: - Table View Subclass

/// NSTableView subclass that adjusts selection on right-click (Finder behavior).
@MainActor
final class FileTableView: NSTableView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)

        if clickedRow >= 0 {
            if !selectedRowIndexes.contains(clickedRow) {
                selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
            }
        } else {
            deselectAll(nil)
        }

        return (dataSource as? FileTableCoordinator)?.buildContextMenu(for: self)
    }
}

// MARK: - NSViewRepresentable

struct NativeFileTableView: NSViewRepresentable {
    let items: [FileItem]
    @Binding var selection: Set<String>
    let appState: AppState
    let onOpenInNewWindow: (URL) -> Void

    func makeCoordinator() -> FileTableCoordinator {
        FileTableCoordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = FileTableView()
        tableView.style = .inset
        tableView.rowHeight = TableLayout.rowHeight
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.doubleAction = #selector(FileTableCoordinator.handleDoubleClick(_:))
        tableView.target = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)

        addColumn(to: tableView, id: ColumnID.name, title: "Name",
                  minWidth: TableLayout.nameColumnMinWidth, width: TableLayout.nameColumnWidth,
                  sortKey: "name")
        addColumn(to: tableView, id: ColumnID.dateModified, title: "Date Modified",
                  minWidth: TableLayout.dateColumnMinWidth, width: TableLayout.dateColumnWidth,
                  sortKey: "dateModified")
        addColumn(to: tableView, id: ColumnID.size, title: "Size",
                  minWidth: TableLayout.sizeColumnMinWidth, width: TableLayout.sizeColumnWidth,
                  sortKey: "size")

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        context.coordinator.tableView = tableView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        if coordinator.currentItems != items {
            let scrollOrigin = scrollView.contentView.bounds.origin

            // Retain icons for items still present by path
            let newIds = Set(items.map(\.id))
            coordinator.iconCache = coordinator.iconCache.filter { newIds.contains($0.key) }

            coordinator.currentItems = items
            coordinator.tableView?.reloadData()

            // Restore scroll position after reload
            scrollView.contentView.scroll(to: scrollOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        coordinator.syncSelection()
        coordinator.syncSortIndicator()
        coordinator.handleRenameState()
    }

    private func addColumn(to table: NSTableView, id: NSUserInterfaceItemIdentifier, title: String,
                           minWidth: CGFloat, width: CGFloat, sortKey: String) {
        let column = NSTableColumn(identifier: id)
        column.title = title
        column.minWidth = minWidth
        column.width = width
        column.sortDescriptorPrototype = NSSortDescriptor(key: sortKey, ascending: true)
        table.addTableColumn(column)
    }
}

// MARK: - Coordinator

@MainActor
final class FileTableCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var parent: NativeFileTableView
    weak var tableView: NSTableView?
    var currentItems: [FileItem] = []
    var iconCache: [String: NSImage] = [:]

    private var isSyncingSelection = false
    private var isSyncingSort = false
    private weak var editingTextField: NSTextField?

    init(_ parent: NativeFileTableView) {
        self.parent = parent
    }

    // MARK: - Data Source

    func numberOfRows(in tableView: NSTableView) -> Int {
        currentItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < currentItems.count else { return nil }
        let item = currentItems[row]

        switch tableColumn?.identifier {
        case ColumnID.name:
            return makeNameCell(for: item, in: tableView, row: row)
        case ColumnID.dateModified:
            return makeTextCell(in: tableView, id: CellID.date, text: item.formattedDate,
                                alignment: .left, mono: false, dimmed: item.isHidden)
        case ColumnID.size:
            return makeTextCell(in: tableView, id: CellID.size, text: item.formattedSize,
                                alignment: .right, mono: true, dimmed: item.isHidden)
        default:
            return nil
        }
    }

    // MARK: - Cell Factories

    private func makeNameCell(for item: FileItem, in tableView: NSTableView, row: Int) -> NSTableCellView {
        let cell = tableView.makeView(withIdentifier: CellID.name, owner: nil) as? NSTableCellView
            ?? createNameCell()

        cell.textField?.stringValue = item.name
        cell.textField?.isEditable = false
        cell.alphaValue = item.isHidden ? 0.5 : 1.0

        if let cached = iconCache[item.id] {
            cell.imageView?.image = cached
        } else {
            let placeholder = item.isDirectory ? "folder.fill" : "doc"
            cell.imageView?.image = NSImage(systemSymbolName: placeholder, accessibilityDescription: nil)
            loadIcon(for: item, in: tableView, row: row)
        }

        return cell
    }

    private func createNameCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = CellID.name

        let iv = NSImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.imageScaling = .scaleProportionallyUpOrDown
        cell.addSubview(iv)
        cell.imageView = iv

        let tf = NSTextField(labelWithString: "")
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.lineBreakMode = .byTruncatingMiddle
        tf.cell?.truncatesLastVisibleLine = true
        cell.addSubview(tf)
        cell.textField = tf

        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: TableLayout.cellPadding),
            iv.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: TableLayout.iconSize),
            iv.heightAnchor.constraint(equalToConstant: TableLayout.iconSize),
            tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: TableLayout.iconTextSpacing),
            tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -TableLayout.cellPadding),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }

    private func makeTextCell(in tableView: NSTableView, id: NSUserInterfaceItemIdentifier,
                              text: String, alignment: NSTextAlignment, mono: Bool, dimmed: Bool) -> NSTableCellView {
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView
            ?? createTextCell(id: id, alignment: alignment, mono: mono)
        cell.textField?.stringValue = text
        cell.alphaValue = dimmed ? 0.5 : 1.0
        return cell
    }

    private func createTextCell(id: NSUserInterfaceItemIdentifier, alignment: NSTextAlignment, mono: Bool) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id

        let tf = NSTextField(labelWithString: "")
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.alignment = alignment
        tf.textColor = .secondaryLabelColor
        tf.lineBreakMode = .byTruncatingTail
        if mono { tf.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular) }
        cell.addSubview(tf)
        cell.textField = tf

        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: TableLayout.cellPadding),
            tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -TableLayout.cellPadding),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }

    // MARK: - Icon Loading

    private func loadIcon(for item: FileItem, in tableView: NSTableView, row: Int) {
        let itemId = item.id
        Task {
            let icon = await IconProvider.icon(for: item)
            self.iconCache[itemId] = icon
            guard row < self.currentItems.count, self.currentItems[row].id == itemId else { return }
            let col = tableView.column(withIdentifier: ColumnID.name)
            guard col >= 0 else { return }
            tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: col))
        }
    }

    // MARK: - Selection

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncingSelection, let tv = notification.object as? NSTableView else { return }
        isSyncingSelection = true
        defer { isSyncingSelection = false }

        parent.selection = Set(tv.selectedRowIndexes.compactMap { row in
            row < currentItems.count ? currentItems[row].id : nil
        })

        parent.appState.updateQuickLookIfVisible()
    }

    func syncSelection() {
        guard !isSyncingSelection, let tv = tableView else { return }
        isSyncingSelection = true
        defer { isSyncingSelection = false }

        let desired = IndexSet(currentItems.indices.filter { parent.selection.contains(currentItems[$0].id) })
        if tv.selectedRowIndexes != desired {
            tv.selectRowIndexes(desired, byExtendingSelection: false)
        }
    }

    // MARK: - Sorting

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !isSyncingSort,
              let desc = tableView.sortDescriptors.first,
              let key = desc.key else { return }

        let field: SortField = switch key {
        case "dateModified": .dateModified
        case "size": .size
        default: .name
        }

        let direction: SortDirection = desc.ascending ? .ascending : .descending
        parent.appState.directory.sort = SortCriteria(field: field, direction: direction)
    }

    func syncSortIndicator() {
        guard let tv = tableView else { return }
        let sort = parent.appState.directory.sort
        let key = switch sort.field {
        case .name: "name"
        case .dateModified: "dateModified"
        case .size: "size"
        }
        let desc = NSSortDescriptor(key: key, ascending: sort.direction == .ascending)
        if tv.sortDescriptors.first != desc {
            isSyncingSort = true
            tv.sortDescriptors = [desc]
            isSyncingSort = false
        }
    }

    // MARK: - Double Click

    @objc func handleDoubleClick(_ sender: NSTableView) {
        let row = sender.clickedRow
        guard row >= 0, row < currentItems.count else { return }
        let item = currentItems[row]

        if item.isDirectory {
            Task { await parent.appState.navigate(to: item.url) }
        } else {
            FileSystemService.open(item.url)
        }
    }

    // MARK: - Drag Source

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard row < currentItems.count else { return nil }
        return currentItems[row].url as NSURL
    }

    // MARK: - Drop Target

    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int, proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        let isInternal = info.draggingSource as? NSTableView === tableView

        // Drop ON a directory row → move into that folder
        if op == .on, row >= 0, row < currentItems.count, currentItems[row].isDirectory {
            return .move
        }

        // Internal drag onto non-folder / background → no-op
        if isInternal {
            return []
        }

        // External drop → copy to current directory
        tableView.setDropRow(-1, dropOperation: .on)
        return .copy
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else { return false }

        if dropOperation == .on, row >= 0, row < currentItems.count, currentItems[row].isDirectory {
            parent.appState.dropItems(urls: urls, to: currentItems[row].url, asCopy: false)
        } else {
            parent.appState.dropItems(urls: urls, to: parent.appState.navigation.currentDirectory, asCopy: true)
        }
        return true
    }

    // MARK: - Context Menu

    func buildContextMenu(for tableView: NSTableView) -> NSMenu {
        let menu = NSMenu()
        let items = selectedItems(in: tableView)
        let single = items.count == 1 ? items.first : nil
        let hasPaste = pasteboardHasFileURLs()

        // Section 1: Open actions
        if !items.isEmpty {
            addMenuItem(to: menu, title: "Open", action: #selector(ctxOpen))
        }
        if let item = single {
            addMenuItem(to: menu, title: "Open With…", action: #selector(ctxOpenWith(_:)), representedObject: item)
        }
        if let item = single, item.isDirectory {
            addMenuItem(to: menu, title: "Open in New Window", action: #selector(ctxOpenInNewWindow(_:)), representedObject: item)
        }
        if let item = single {
            addMenuItem(to: menu, title: "Reveal in Finder", action: #selector(ctxRevealInFinder(_:)), representedObject: item)
        }
        if let item = single {
            addMenuItem(to: menu, title: "Rename", action: #selector(ctxRename(_:)), representedObject: item)
        }

        // Section 2: Clipboard actions
        if !items.isEmpty || hasPaste {
            if menu.numberOfItems > 0 { menu.addItem(.separator()) }
            if !items.isEmpty {
                addMenuItem(to: menu, title: "Copy", action: #selector(ctxCopy))
            }
            if hasPaste {
                addMenuItem(to: menu, title: "Paste", action: #selector(ctxPaste))
            }
            if !items.isEmpty {
                addMenuItem(to: menu, title: "Copy Path", action: #selector(ctxCopyPath))
            }
        }

        // Section 3: Destructive
        if !items.isEmpty {
            menu.addItem(.separator())
            addMenuItem(to: menu, title: "Move to Trash", action: #selector(ctxTrash))
        }

        // Section 4: Info
        if let item = single {
            menu.addItem(.separator())
            addMenuItem(to: menu, title: "Get Info", action: #selector(ctxGetInfo(_:)), representedObject: item)
        }

        return menu
    }

    private func addMenuItem(to menu: NSMenu, title: String, action: Selector, representedObject: Any? = nil) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = representedObject
    }

    private func selectedItems(in tableView: NSTableView) -> [FileItem] {
        tableView.selectedRowIndexes.compactMap { row in
            row < currentItems.count ? currentItems[row] : nil
        }
    }

    private func pasteboardHasFileURLs() -> Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    // MARK: - Menu Actions

    @objc private func ctxOpen() {
        parent.appState.openSelectedItems()
    }

    @objc private func ctxOpenWith(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? FileItem else { return }
        FileSystemService.openWith(item.url)
    }

    @objc private func ctxOpenInNewWindow(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? FileItem else { return }
        parent.onOpenInNewWindow(item.url)
    }

    @objc private func ctxRename(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? FileItem else { return }
        parent.appState.startRenaming(item)
    }

    @objc private func ctxCopy() {
        parent.appState.copySelectedItems()
    }

    @objc private func ctxPaste() {
        parent.appState.pasteItems()
    }

    @objc private func ctxCopyPath() {
        guard let tv = tableView else { return }
        let items = selectedItems(in: tv)
        guard !items.isEmpty else { return }
        if items.count == 1, let item = items.first {
            FileSystemService.copyPath(item.url)
        } else {
            let paths = items.map { $0.url.path(percentEncoded: false) }.joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(paths, forType: .string)
        }
    }

    @objc private func ctxTrash() {
        parent.appState.trashSelectedItems()
    }

    @objc private func ctxRevealInFinder(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? FileItem else { return }
        FileSystemService.revealInFinder(item.url)
    }

    @objc private func ctxGetInfo(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? FileItem else { return }
        FileSystemService.showGetInfo(item.url)
    }

    // MARK: - Inline Rename

    func handleRenameState() {
        guard let tv = tableView else { return }

        if let renamingItem = parent.appState.renamingItem {
            guard let row = currentItems.firstIndex(where: { $0.id == renamingItem.id }) else {
                parent.appState.cancelRename()
                return
            }
            let col = tv.column(withIdentifier: ColumnID.name)
            guard col >= 0,
                  let cell = tv.view(atColumn: col, row: row, makeIfNecessary: false) as? NSTableCellView,
                  let tf = cell.textField else { return }

            // Already editing this cell — skip
            guard tf.currentEditor() == nil else { return }

            editingTextField = tf
            tf.isEditable = true
            tf.delegate = self
            tf.stringValue = parent.appState.renameText
            // Defer focus to next runloop — makeFirstResponder fails if called during
            // a SwiftUI update while a context menu is still dismissing.
            let name = renamingItem.name
            let isDir = renamingItem.isDirectory
            DispatchQueue.main.async { [weak self] in
                tv.window?.makeFirstResponder(tf)
                self?.selectStem(in: tf, name: name, isDirectory: isDir)
            }
        } else if let tf = editingTextField {
            // Clean up after Escape (abortEditing doesn't post controlTextDidEndEditing)
            tf.isEditable = false
            tf.delegate = nil
            editingTextField = nil
        }
    }

    /// Select just the filename stem (before the last dot) in the text field.
    private func selectStem(in tf: NSTextField, name: String, isDirectory: Bool) {
        // Directories and dotfiles: select all
        let ext = (name as NSString).pathExtension
        if isDirectory || ext.isEmpty || name.hasPrefix(".") {
            tf.selectText(nil)
            return
        }
        let stemLength = name.count - ext.count - 1 // exclude the dot
        guard stemLength > 0,
              let editor = tf.currentEditor() else {
            tf.selectText(nil)
            return
        }
        editor.selectedRange = NSRange(location: 0, length: stemLength)
    }
}

// MARK: - Rename Text Field Delegate

extension FileTableCoordinator: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let tf = obj.object as? NSTextField else { return }
        tf.isEditable = false
        tf.delegate = nil
        editingTextField = nil

        let movement = (obj.userInfo?["NSTextMovement"] as? Int) ?? 0
        if movement == NSTextMovement.return.rawValue {
            parent.appState.renameText = tf.stringValue
            parent.appState.commitRename()
        } else {
            parent.appState.cancelRename()
        }
    }
}
