//
//  ScoreViewModel.swift
//  BTrank
//

import SwiftUI

/// 评分输入框的问题类型
enum InputIssue {
    case notNumber      // 不是有效数字
    case outOfRange     // 不在 0–10 之间

    /// 输入框下方的红色提示
    var inlineMessage: String {
        switch self {
        case .notNumber: return "无效数字，请输入 0–10 之间的数字"
        case .outOfRange: return "超出范围，请输入 0–10 之间的数字"
        }
    }

    /// 点击「计算分数」时的红色提示（前面接维度名）
    func calculationMessage(for dimension: Dimension) -> String {
        switch self {
        case .notNumber: return "\(dimension.title)输入的不是有效数字"
        case .outOfRange: return "\(dimension.title)分数不在 0–10 范围内"
        }
    }
}

final class ScoreViewModel: ObservableObject {
    // 输入
    @Published var name: String = ""
    @Published var baseScore: String = ""
    @Published var bodyScore: String = ""
    @Published var dressing: String = ""
    @Published var temperament: String = ""
    @Published var personalityScore: String = ""
    @Published var adjustments = Adjustments()

    // 计算结果
    @Published var calculatedScore: Double?
    @Published var calculatedDims: [Double]?
    @Published var justAdded = false
    /// 用户在输入不合法时点过「计算分数」：显示红色提示，直到输入改对
    @Published var showCalcError = false

    // 排行榜数据（每次修改自动保存）
    @Published var people: [Person] = [] {
        didSet { savePeople() }
    }

    private let storeKey = "PersonList"
    private let legacyKey = "ScoreList"

    init() {
        loadPeople()
    }

    /// 按平均分从高到低
    var rankedPeople: [Person] {
        people.sorted { $0.averageScore > $1.averageScore }
    }

    // MARK: 计算

    /// 某一维度当前的输入文本
    private func text(for dimension: Dimension) -> String {
        switch dimension {
        case .base: return baseScore
        case .body: return bodyScore
        case .dressing: return dressing
        case .temperament: return temperament
        case .personality: return personalityScore
        }
    }

    /// 把输入转成数字：空按 0，逗号当小数点；不是数字返回 nil
    private func number(from text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if normalized.isEmpty { return 0 }
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    /// 某一维度输入的问题；nil = 合法（空按 0 处理）
    func issue(for dimension: Dimension) -> InputIssue? {
        guard let value = number(from: text(for: dimension)) else { return .notNumber }
        return (value < 0 || value > 10) ? .outOfRange : nil
    }

    /// 点击「计算分数」被拒绝后的红色提示；输入改对后自动消失
    var calculationErrorMessage: String? {
        guard showCalcError else { return nil }
        let parts = Dimension.allCases.compactMap { dim in
            issue(for: dim).map { $0.calculationMessage(for: dim) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "；") + "，无法计算"
    }

    func calculateScore() {
        // 任何一项不合法就不计算，也不保留上一次的结果
        guard Dimension.allCases.allSatisfy({ issue(for: $0) == nil }) else {
            showCalcError = true
            calculatedScore = nil
            calculatedDims = nil
            justAdded = false
            return
        }
        showCalcError = false
        let dims = Dimension.allCases.map { number(from: text(for: $0)) ?? 0 }
        calculatedDims = dims
        calculatedScore = ScoreEngine.score(raw: dims, adjustments: adjustments)
        justAdded = false
    }

    // MARK: 排行榜

    private func trimmedName() -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func existingPerson(named rawName: String) -> Person? {
        let target = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }
        return people.first { $0.name.caseInsensitiveCompare(target) == .orderedSame }
    }

    func addToRanking() {
        guard let score = calculatedScore, let dims = calculatedDims, !justAdded else { return }
        let cleanName = trimmedName()
        guard !cleanName.isEmpty else { return }

        let entry = ScoreEntry(id: UUID(), date: Date(), score: score, dims: dims, note: adjustments.summary)

        if let index = people.firstIndex(where: { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) {
            people[index].entries.append(entry)
        } else {
            people.append(Person(id: UUID(), name: cleanName, entries: [entry]))
        }
        justAdded = true
    }

    func removePeople(ids: [UUID]) {
        people.removeAll { ids.contains($0.id) }
    }

    func removeEntries(ids: [UUID], from personID: UUID) {
        guard let index = people.firstIndex(where: { $0.id == personID }) else { return }
        people[index].entries.removeAll { ids.contains($0.id) }
        if people[index].entries.isEmpty {
            people.remove(at: index)
        }
    }

    func resetInputs() {
        baseScore = ""; bodyScore = ""
        dressing = ""; temperament = ""; personalityScore = ""
        calculatedScore = nil
        calculatedDims = nil
        justAdded = false
        showCalcError = false
    }

    // MARK: 持久化

    private func savePeople() {
        if let data = try? JSONEncoder().encode(people) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    private func loadPeople() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: storeKey),
           let decoded = try? JSONDecoder().decode([Person].self, from: data) {
            people = decoded
            return
        }
        // 迁移旧版本数据：每个旧记录变成一个人的第一次评分
        if let data = defaults.data(forKey: legacyKey),
           let legacy = try? JSONDecoder().decode([LegacyUserScore].self, from: data) {
            people = legacy.map {
                Person(id: $0.id, name: $0.name,
                       entries: [ScoreEntry(id: UUID(), date: Date(), score: $0.score, dims: nil, note: "旧版本数据")])
            }
        }
    }
}
