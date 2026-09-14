import Foundation

/// Multi-pane layout configuration supporting single, horizontal dual, vertical dual, and 4-way grid splits (F-004).
enum SplitLayout: Int, CaseIterable, Identifiable {
    case single = 0        // 1 pane
    case horizontal2 = 1   // 2 columns (Left | Right)
    case vertical2 = 2     // 2 rows (Top / Bottom)
    case quad4 = 3         // 4 grid (2x2)

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .single: return "Single"
        case .horizontal2: return "2 Columns"
        case .vertical2: return "2 Rows"
        case .quad4: return "4 Grid"
        }
    }

    var iconName: String {
        switch self {
        case .single: return "rectangle"
        case .horizontal2: return "rectangle.split.2x1"
        case .vertical2: return "rectangle.split.1x2"
        case .quad4: return "rectangle.split.2x2"
        }
    }

    var paneCount: Int {
        switch self {
        case .single: return 1
        case .horizontal2, .vertical2: return 2
        case .quad4: return 4
        }
    }
}
