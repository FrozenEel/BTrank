//  BTrankApp.swift

import SwiftUI

struct UserScore: Identifiable, Codable {
    let id: UUID
    let name: String
    let score: Double
}

class ScoreViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var baseScore: String = ""
    @Published var bodyScore: String = ""
    @Published var makeup: String = ""
    @Published var filter: String = ""
    @Published var dressing: String = ""
    @Published var temperament: String = ""
    @Published var isInfluencer: Bool = false

    @Published var scoreList: [UserScore] = [] {
        didSet { saveScoreList() }
    }

    @Published var calculatedScore: Double?

    init() {
        loadScoreList()
    }

    func calculateScore() {
        let R = Double(baseScore) ?? 0
        let B = Double(bodyScore) ?? 0
        let M = Double(makeup) ?? 0
        let F = Double(filter) ?? 0
        let C = Double(dressing) ?? 0
        let L = Double(temperament) ?? 0
        let K1 = isInfluencer ? 1.02 : 1.0

        //smooth log
        let gR = log(R + 1)
        let gB = log(B + 1)
        let gM = log(M + 1)
        let gF = log(F + 1)
        let gC = log(C + 1)
        let gL = log(L + 1)

        //normalized log
        func f(_ x: Double) -> Double {
            return x / log(11)
        }

        let normalizedR = f(gR)
        let normalizedB = f(gB)
        let normalizedC = f(gC)
        let normalizedL = f(gL)

        // 动态权重示例：基础颜值低，身材占比提高
        let beautyWeight = normalizedR < 0.3 ? 0.45 : 0.35
        let bodyWeight = 0.7 - beautyWeight

        // 多化妆/滤镜扣分
        let makeupEffect = 1 - 0.2 * f(gM)
        let filterEffect = 1 - 0.05 * f(gF)

        // 综合打分
        let score = (beautyWeight * normalizedR + bodyWeight * normalizedB + 0.1 * normalizedC + 0.2 * normalizedL)
                    * makeupEffect * filterEffect * K1 * 10

        calculatedScore = max(0, min(score, 10))
    }

    func addToRanking() {
        guard let score = calculatedScore, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        if let index = scoreList.firstIndex(where: { $0.name == name }) {
            scoreList[index] = UserScore(id: scoreList[index].id, name: name, score: score)
        } else {
            let newUser = UserScore(id: UUID(), name: name, score: score)
            scoreList.append(newUser)
        }
        scoreList.sort { $0.score > $1.score }
    }

    private func saveScoreList() {
        if let data = try? JSONEncoder().encode(scoreList) {
            UserDefaults.standard.set(data, forKey: "ScoreList")
        }
    }

    private func loadScoreList() {
        if let data = UserDefaults.standard.data(forKey: "ScoreList"),
           let decoded = try? JSONDecoder().decode([UserScore].self, from: data) {
            scoreList = decoded
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ScoreViewModel()
    @State private var showRanking = false

    var body: some View {
        NavigationView {
            CalculationView(viewModel: viewModel)
                .navigationTitle("计算评分")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("排行榜") {
                            UIApplication.shared.endEditing()
                            showRanking = true
                        }
                    }
                }
                .sheet(isPresented: $showRanking) {
                    RankingView(viewModel: viewModel)
                        .presentationDetents([.medium, .large])
                }
        }
    }
}

struct CalculationView: View {
    @ObservedObject var viewModel: ScoreViewModel

    var body: some View {
        Form {
            Section(header: Text("输入信息")) {
                HStack {
                    Text("姓名")
                    Spacer()
                    TextField("", text: $viewModel.name)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("基础颜值 (0-10)")
                    Spacer()
                    TextField("", text: $viewModel.baseScore)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("身材打分 (0-10)")
                    Spacer()
                    TextField("", text: $viewModel.bodyScore)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("化妆浓度 (0-10)")
                    Spacer()
                    TextField("", text: $viewModel.makeup)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("滤镜强度 (0-10)")
                    Spacer()
                    TextField("", text: $viewModel.filter)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("穿搭打分 (0-10)")
                    Spacer()
                    TextField("", text: $viewModel.dressing)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("气质打分 (0-10)")
                    Spacer()
                    TextField("", text: $viewModel.temperament)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                Toggle("学历补正", isOn: $viewModel.isInfluencer)
            }

            Button("计算分数") {
                viewModel.calculateScore()
                UIApplication.shared.endEditing()
            }

            if let score = viewModel.calculatedScore {
                Text(String(format: "计算结果：%.3f", score))
                    .font(.headline)
                    .padding(.top)

                Button("加入排行榜") {
                    viewModel.addToRanking()
                }
            }
        }
    }
}

struct RankingView: View {
    @ObservedObject var viewModel: ScoreViewModel
    @State private var showDeleteAlert = false
    @State private var indexToDelete: IndexSet?

    var body: some View {
        NavigationView {
            List {
                ForEach(Array(viewModel.scoreList.enumerated()), id: \.element.id) { index, user in
                    if !user.name.trimmingCharacters(in: .whitespaces).isEmpty {
                        HStack {
                            Text("\(index + 1). \(user.name)")
                            Spacer()
                            Text(String(format: "%.3f", user.score))
                        }
                    }
                }
                .onDelete { offsets in
                    indexToDelete = offsets
                    showDeleteAlert = true
                }
            }
            .navigationTitle("排行榜")
            .alert(isPresented: $showDeleteAlert) {
                Alert(
                    title: Text("确认删除"),
                    message: Text("确定要删除该排位吗？"),
                    primaryButton: .destructive(Text("删除")) {
                        if let indexSet = indexToDelete {
                            viewModel.scoreList.remove(atOffsets: indexSet)
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }
}

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
