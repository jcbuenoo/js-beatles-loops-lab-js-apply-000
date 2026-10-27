import PauseCore
import SwiftUI

/// Intentional / neutral / distracting as one stacked bar.
struct CategoryBar: View {
    let report: DayReport

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                if report.totalActive > 0 {
                    ForEach(AppCategory.allCases) { category in
                        let share = report.share(of: category)
                        if share > 0 {
                            Rectangle()
                                .fill(category.color)
                                .frame(width: max(2, geo.size.width * share))
                        }
                    }
                } else {
                    Rectangle().fill(Color.secondary.opacity(0.2))
                }
            }
            .clipShape(Capsule())
        }
    }
}

extension AppCategory {
    var color: Color {
        switch self {
        case .intentional: return .green
        case .neutral: return .gray
        case .distracting: return .orange
        }
    }
}
