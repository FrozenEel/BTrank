//
//  RadarChartView.swift
//  BTrank
//

import SwiftUI

/// 多边形：按 values（0...maxValue）在各个轴上取点
struct RadarPolygon: Shape {
    var values: [Double]
    var maxValue: Double = 10

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let n = values.count
        guard n >= 3 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        for (i, v) in values.enumerated() {
            let ratio = min(max(v / maxValue, 0), 1)
            let angle = -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(n)
            let point = CGPoint(x: center.x + CGFloat(cos(angle) * ratio) * radius,
                                y: center.y + CGFloat(sin(angle) * ratio) * radius)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// 从中心到各顶点的轴线
struct RadarAxes: Shape {
    var count: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard count >= 3 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        for i in 0..<count {
            let angle = -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(count)
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * radius,
                                     y: center.y + CGFloat(sin(angle)) * radius))
        }
        return path
    }
}

struct RadarChartView: View {
    /// 0...10，顺序与 labels 一致
    let values: [Double]
    var labels: [String] = Dimension.titles
    var showLabels: Bool = true
    var accent: Color = .pink

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = showLabels ? 36 : 2
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2 - inset
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                ZStack {
                    // 2 / 4 / 6 / 8 / 10 五圈网格
                    ForEach(1...5, id: \.self) { ring in
                        RadarPolygon(values: Array(repeating: Double(ring) * 2, count: values.count))
                            .stroke(Color.gray.opacity(0.35), lineWidth: 0.6)
                    }
                    RadarAxes(count: values.count)
                        .stroke(Color.gray.opacity(0.35), lineWidth: 0.6)
                    RadarPolygon(values: values)
                        .fill(accent.opacity(0.28))
                    RadarPolygon(values: values)
                        .stroke(accent, lineWidth: showLabels ? 2 : 1.2)
                }
                .frame(width: max(radius, 0) * 2, height: max(radius, 0) * 2)
                .position(center)

                if showLabels {
                    ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                        let angle = -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(values.count)
                        let r = radius + 22
                        VStack(spacing: 0) {
                            Text(i < labels.count ? labels[i] : "")
                                .font(.caption2)
                            Text(String(format: "%.1f", v))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(accent)
                        }
                        .position(x: center.x + CGFloat(cos(angle)) * r,
                                  y: center.y + CGFloat(sin(angle)) * r)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
