import Foundation

/// Column by which the file list can be sorted.
enum SortField: String, CaseIterable, Sendable {
    case name
    case dateModified
    case size
}

/// Sort direction.
enum SortDirection: Sendable {
    case ascending
    case descending

    mutating func toggle() {
        self = (self == .ascending) ? .descending : .ascending
    }
}

/// Complete sort specification: field + direction.
struct SortCriteria: Sendable {
    var field: SortField
    var direction: SortDirection

    static let `default` = SortCriteria(field: .name, direction: .ascending)
}

extension SortCriteria {
    /// Returns a comparator closure for sorting `FileItem` arrays.
    /// Directories are always grouped before files regardless of sort field.
    var comparator: (FileItem, FileItem) -> Bool {
        { lhs, rhs in
            // Directories first
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }

            let result: ComparisonResult
            switch field {
            case .name:
                result = lhs.name.localizedStandardCompare(rhs.name)
            case .dateModified:
                let lDate = lhs.dateModified ?? .distantPast
                let rDate = rhs.dateModified ?? .distantPast
                result = lDate.compare(rDate)
            case .size:
                let lSize = lhs.size ?? 0
                let rSize = rhs.size ?? 0
                if lSize == rSize { result = .orderedSame }
                else { result = lSize < rSize ? .orderedAscending : .orderedDescending }
            }

            switch direction {
            case .ascending:
                return result == .orderedAscending
            case .descending:
                return result == .orderedDescending
            }
        }
    }
}
