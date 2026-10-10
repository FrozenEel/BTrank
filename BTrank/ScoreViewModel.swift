//
//  ScoreViewModel.swift
//  BTrank
//

import SwiftUI

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

    /// 解析输入：空或非法 → 0，并限制在 0...10
    private func parse(_ text: String) -> Double {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let value = Double(normalized) ?? 0
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 10)
    }

    func calculateScore() {
        let dims = [baseScore, bodyScore, dressing, temperament, personalityScore].map(parse)
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
