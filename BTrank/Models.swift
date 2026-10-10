//
//  Models.swift
//  BTrank
//
//  数据模型 + 评分引擎
//

import Foundation

// MARK: - 评分维度（颜值、身材、穿搭、气质、性格；雷达图的五个轴，各 0...10）

enum Dimension: Int, CaseIterable {
    case base, body, dressing, temperament, personality

    /// 雷达图上的短名称
    var title: String {
        switch self {
        case .base: return "颜值"
        case .body: return "身材"
        case .dressing: return "穿搭"
        case .temperament: return "气质"
        case .personality: return "性格"
        }
    }

    /// 输入表单里的名称（与雷达图一致）
    var fullTitle: String { title }

    static var titles: [String] { allCases.map(\.title) }
}

// MARK: - 补正选项
//
// 一、加分补正（走「补正强度」，满额 = 100%）
//   学历 / 事业  二选一（或都不选）：选其一 +1 点
//   上镜度      无（上镜，指原始面容，不变）/ 有（不上镜，本人比镜头里好看，+1 点）
//   满额 = 学历或事业 + 不上镜 = 2 点 = 强度 100%，规则见 ScoreEngine.applyAdjustments：
//     综合基础分 < 6：  满额 +0.5 分
//     综合基础分 ≥ 6：  满额 ×1.125（8 分 → 9 分）
//   舍得        三选一：共同承担（不加不扣）/ 舍得（愿意为伴侣花钱）/ 不舍得（不愿在情感中花钱）
//               排在财富之后，不走点数：
//               舍得   指数曲线，分越高加得越多（4 分以下不加，5 分 +0.5，7 分 +2.1 → 9.1），见 generosityBonus
//               不舍得 非线性扣分，分越高扣得越少（5 分及以下扣 2 分，7 分以下从 0.7 起扣，7 分及以上不扣，扣到 0 为止），见 stingyPenalty
//   财富        不走点数：有则综合基础分低于 8 的按 8 算，不低于 8 的不变
//
// 二、扣分补正（另一套规则：不管分数高低，一律按百分比相乘）
//   化妆 / 滤镜  无 0 / 低 −2.083% / 中 −4.167% / 高 −6.25%（各自独立，可叠加）

/// 化妆 / 滤镜的程度：低 / 中 / 高
enum AdjustmentLevel: Int, CaseIterable, Identifiable, Codable {
    case low = 1, medium, high

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }
}

/// 舍得补正：对伴侣在情感上的消费态度（共同承担 = 不加不扣）
enum Generosity: Int, CaseIterable, Identifiable, Codable {
    case none, generous, stingy

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .none: return "共同承担"
        case .generous: return "舍得"
        case .stingy: return "不舍得"
        }
    }
}

/// 学历 / 事业补正：二选一
enum StatusBonus: Int, CaseIterable, Identifiable, Codable {
    case none, education, career

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .none: return "无"
        case .education: return "学历"
        case .career: return "事业"
        }
    }
}

struct Adjustments: Codable, Equatable {
    // 加分补正
    var statusBonus: StatusBonus = .none        // 学历 / 事业：二选一，默认都不选
    var generosity: Generosity = .none          // 舍得：默认「共同承担」（不加不扣），不走点数
    var unphotogenic = false                    // 上镜度补正：默认无（上镜，不变）；有 = 不上镜，加分
    var wealth = false                          // 财富：默认无

    // 扣分补正
    var makeupEnabled = false
    var makeupLevel: AdjustmentLevel = .medium
    var filterEnabled = false
    var filterLevel: AdjustmentLevel = .medium

    // MARK: 加分补正强度

    static let statusPoints = 1.0        // 学历 / 事业（二选一）
    static let cameraPoints = 1.0        // 不上镜

    /// 加分点数
    var points: Double {
        (statusBonus != .none ? Adjustments.statusPoints : 0)
        + (unphotogenic ? Adjustments.cameraPoints : 0)
    }

    /// 满额点数：学历或事业 + 不上镜 = 2
    static let fullPoints = statusPoints + cameraPoints

    /// 补正强度：1.0 = 满额
    var strength: Double { points / Adjustments.fullPoints }

    // MARK: 扣分补正

    /// 化妆 / 滤镜「高」档的最大扣分比例
    static let maxDeduction = 0.0625

    private func deduction(enabled: Bool, level: AdjustmentLevel) -> Double {
        enabled ? Adjustments.maxDeduction * Double(level.rawValue) / 3 : 0
    }

    var makeupDeduction: Double { deduction(enabled: makeupEnabled, level: makeupLevel) }
    var filterDeduction: Double { deduction(enabled: filterEnabled, level: filterLevel) }

    /// 扣分总乘数 = (1 − 化妆扣分) × (1 − 滤镜扣分)
    var deductionMultiplier: Double {
        (1 - makeupDeduction) * (1 - filterDeduction)
    }

    /// 历史记录里显示的补正摘要
    var summary: String {
        var parts: [String] = []
        if statusBonus != .none { parts.append(statusBonus.title) }
        if generosity != .none { parts.append(generosity.title) }
        if unphotogenic { parts.append("不上镜") }
        if wealth { parts.append("财富") }
        if makeupEnabled { parts.append("化妆·\(makeupLevel.title)") }
        if filterEnabled { parts.append("滤镜·\(filterLevel.title)") }
        return parts.isEmpty ? "无补正" : parts.joined(separator: " / ")
    }
}

// MARK: - 评分引擎

enum ScoreEngine {
    /// raw 按 Dimension 顺序：颜值、身材、穿搭、气质、性格，每项 0...10
    static func score(raw: [Double], adjustments: Adjustments) -> Double {
        guard raw.count == Dimension.allCases.count else { return 0 }

        // 归一化：线性 x / 10，输入 0...10 → 输出 0...1（5 分 = 0.5）
        func f(_ x: Double) -> Double { min(max(x / 10, 0), 1) }

        let r = f(raw[Dimension.base.rawValue])
        let b = f(raw[Dimension.body.rawValue])
        let c = f(raw[Dimension.dressing.rawValue])
        let l = f(raw[Dimension.temperament.rawValue])
        let p = f(raw[Dimension.personality.rawValue])

        // 权重：颜值 + 身材 = 0.6；基础颜值低（< 0.3）时颜值 0.27 / 身材 0.33，否则各 0.30
        let beautyWeight = r < 0.3 ? 0.27 : 0.30
        let bodyWeight = 0.6 - beautyWeight

        // 综合基础分（0...10）：颜值/身材 0.6，穿搭 0.15，气质 0.10，性格 0.15
        var base = (beautyWeight * r + bodyWeight * b + 0.15 * c + 0.10 * l + 0.15 * p) * 10

        // 财富补正：综合基础分低于 wealthBase 的，按 wealthBase 算；不低于的不受影响
        if adjustments.wealth { base = max(base, wealthBase) }

        // 舍得补正：在财富补正之后计算
        switch adjustments.generosity {
        case .none: break
        case .generous: base += generosityBonus(base: base)
        case .stingy: base = max(0, base - stingyPenalty(base: base))
        }

        // 加分补正
        var score = applyAdjustments(base: base, strength: adjustments.strength)

        // 扣分补正：另一套规则，一律按百分比相乘，最后再封顶
        score *= adjustments.deductionMultiplier

        return max(0, min(score, 10))
    }

    // MARK: 舍得补正（指数曲线）

    /// 综合基础分不高于它时，完全没有舍得补正
    static let generosityStart = 4.0
    /// 综合基础分达到它时补正最大，之后不再增加（7 分 → 9.1 分）
    static let generosityPeak = 7.0
    /// 5 分（比起点高 1 分）时的补正：5 → 5.5
    static let generosityAt5 = 0.5
    /// 7 分（比起点高 3 分）时的补正：7 → 9.1
    static let generosityAtPeak = 2.1

    /// bonus(x) = a·(qˣ − 1)，x = min(基础分, 7) − 4。
    /// 由 bonus(1) = 0.5、bonus(3) = 2.1 解出：q² + q + 1 = 2.1/0.5，a = 0.5/(q − 1)
    /// （只在起点 4、峰值 7、取样点 5 这组数下成立；改这几个数要重新解 q 和 a）
    private static let generosityQ: Double = {
        let ratio = generosityAtPeak / generosityAt5
        return (-1 + (1 + 4 * (ratio - 1)).squareRoot()) / 2
    }()
    private static let generosityA: Double = generosityAt5 / (generosityQ - 1)

    /// 舍得补正加多少分：4 分及以下 0，之后按指数上升，7 分及以上固定在 +2.1
    static func generosityBonus(base: Double) -> Double {
        guard base > generosityStart else { return 0 }
        let x = min(base, generosityPeak) - generosityStart
        return generosityA * (pow(generosityQ, x) - 1)
    }

    // MARK: 不舍得补正（非线性扣分）

    /// 综合基础分不高于它时，扣满 stingyMax
    static let stingyFullAt = 5.0
    /// 综合基础分不低于它时，不扣分
    static let stingyNoneAt = 7.0
    /// 最多扣多少分：5 分扣到 3 分；5 分以下同样扣 2 分，扣到 0 为止
    static let stingyMax = 2.0
    /// 刚低于 7 分时的起扣分数：7 分不扣，6.99 分就从扣 0.7 开始
    static let stingyStart = 0.7
    /// 5 到 7 分之间的衰减指数：2 = 开头扣得快、越接近 7 分扣得越慢
    static let stingyExponent = 2.0

    /// 不舍得扣多少分：≥7 分 0；<7 分从 0.7 起，越低扣得越多，非线性升到 5 分的 2；≤5 分扣 2
    /// penalty = 0.7 + 1.3 × ((7−x)/2)^2，例：6.9 → 0.7，6.5 → 0.78，6 → 1.03，5.5 → 1.43，5 → 2
    static func stingyPenalty(base: Double) -> Double {
        if base >= stingyNoneAt { return 0 }
        if base <= stingyFullAt { return stingyMax }
        let t = (stingyNoneAt - base) / (stingyNoneAt - stingyFullAt)
        return stingyStart + (stingyMax - stingyStart) * pow(t, stingyExponent)
    }

    // MARK: 加分补正的两套算法

    /// 分界线：综合基础分低于它用加法，不低于它用乘法
    static let threshold = 6.0
    /// 补正满额时，低于分界线的人最多加多少分（全 5 分的普通人：5 + 0.5 = 5.5）
    static let fullBonus = 0.5

    /// 财富补正：有则综合基础分低于它的按它算，不低于它的不受影响（之后的补正照常），总分封顶 10
    static let wealthBase = 8.0

    /// 不低于分界线的人，补正满额时的乘数：8 分 × 1.125 = 9 分
    static let fullMultiplier = 1.125

    /// 低于分界线：加法，补正拉满固定 +0.5 分，所有人加得一样多。
    /// 不低于分界线：乘法，补正拉满 ×1.125，分越高加得越多。
    /// 两套算法在分界线处有一个向上的小台阶（5.99 → 6.49，6.0 → 6.75），分数不会倒挂。
    static func applyAdjustments(base: Double, strength: Double) -> Double {
        if base < threshold {
            return base + fullBonus * strength
        } else {
            return base * (1 + (fullMultiplier - 1) * strength)
        }
    }
}

// MARK: - 排行榜数据

/// 一次评分记录
struct ScoreEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    let score: Double
    /// 六项原始分（旧版本迁移来的记录没有）
    let dims: [Double]?
    /// 当时启用的补正摘要
    let note: String
}

/// 一个人，可以有多次评分
struct Person: Identifiable, Codable {
    let id: UUID
    var name: String
    var entries: [ScoreEntry]

    var averageScore: Double {
        guard !entries.isEmpty else { return 0 }
        return entries.map(\.score).reduce(0, +) / Double(entries.count)
    }

    /// 各维度平均分（用于雷达图）；没有任何带维度的记录时为 nil
    var averageDims: [Double]? {
        let all = entries.compactMap(\.dims).filter { $0.count == Dimension.allCases.count }
        guard !all.isEmpty else { return nil }
        return (0..<Dimension.allCases.count).map { i in
            all.map { $0[i] }.reduce(0, +) / Double(all.count)
        }
    }
}

/// 旧版本（单次评分）的数据结构，仅用于迁移
struct LegacyUserScore: Codable {
    let id: UUID
    let name: String
    let score: Double
}
