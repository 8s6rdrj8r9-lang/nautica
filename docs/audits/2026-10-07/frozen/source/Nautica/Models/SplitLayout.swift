import Foundation

/// Multi-pane layout configuration supporting single, 2-way, and 4-way horizontal, vertical, and grid splits (F-004).
enum SplitLayout: Int, CaseIterable, Identifiable {
    case single = 0        // 1 pane
    case horizontal2 = 1   // 2 columns (Left | Right)
    case vertical2 = 2     // 2 rows (Top / Bottom)
    case quad4 = 3         // 4 grid (2x2)
    case horizontal4 = 4   // 4 columns (1 | 2 | 3 | 4)
    case vertical4 = 5     // 4 rows (1 / 2 / 3 / 4)

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .single: return "Single"
        case .horizontal2: return "2 Columns"
        case .vertical2: return "2 Rows"
        case .quad4: return "4 Grid (2x2)"
        case .horizontal4: return "4 Columns"
        case .vertical4: return "4 Rows"
        }
    }

    var iconName: String {
        switch self {
        case .single: return "rectangle"
        case .horizontal2: return "rectangle.split.2x1"
        case .vertical2: return "rectangle.split.1x2"
        case .quad4: return "rectangle.split.2x2"
        case .horizontal4: return "rectangle.split.3x1"
        case .vertical4: return "rectangle.grid.1x2"
        }
    }

    var paneCount: Int {
        switch self {
        case .single: return 1
        case .horizontal2, .vertical2: return 2
        case .quad4, .horizontal4, .vertical4: return 4
        }
    }
}
