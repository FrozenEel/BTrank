//
//  ContentView.swift
//  BTrank
//

import SwiftUI

// MARK: - 主界面

struct ContentView: View {
    @StateObject private var viewModel = ScoreViewModel()
    @State private var showRanking = false

    var body: some View {
        NavigationStack {
            CalculationView(viewModel: viewModel)
                .navigationTitle("计算评分")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
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

// MARK: - 计算页

struct CalculationView: View {
    @ObservedObject var viewModel: ScoreViewModel

    var body: some View {
        Form {
            Section("输入信息") {
                HStack {
                    Text("姓名")
                    Spacer()
                    TextField("", text: $viewModel.name)
                        .multilineTextAlignment(.trailing)
                }
                ScoreField(title: "\(Dimension.base.fullTitle) (0-10)", text: $viewModel.baseScore)
                ScoreField(title: "\(Dimension.body.fullTitle) (0-10)", text: $viewModel.bodyScore)
                ScoreField(title: "\(Dimension.dressing.fullTitle) (0-10)", text: $viewModel.dressing)
                ScoreField(title: "\(Dimension.temperament.fullTitle) (0-10)", text: $viewModel.temperament)
                ScoreField(title: "\(Dimension.personality.fullTitle) (0-10)", text: $viewModel.personalityScore)
            }

            Section("补正") {
                AdjustmentsForm(adj: $viewModel.adjustments)
            }

            Section {
                Button("计算分数") {
                    viewModel.calculateScore()
                    UIApplication.shared.endEditing()
                }
                Button("重置输入", role: .destructive) {
                    viewModel.resetInputs()
                    UIApplication.shared.endEditing()
                }
            }

            if let score = viewModel.calculatedScore, let dims = viewModel.calculatedDims {
                Section("本次结果") {
                    Text(String(format: "计算结果：%.3f", score))
                        .font(.headline)

                    RadarChartView(values: dims)
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)

                    if let person = viewModel.existingPerson(named: viewModel.name) {
                        Text(String(format: "%@ 已评分 %d 次，当前平均 %.3f", person.name, person.entries.count, person.averageScore))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button(viewModel.justAdded ? "已加入排行榜" : "加入排行榜") {
                        viewModel.addToRanking()
                        UIApplication.shared.endEditing()
                    }
                    .disabled(viewModel.justAdded
                              || viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct ScoreField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - 补正选项

struct LevelPicker: View {
    @Binding var level: AdjustmentLevel

    var body: some View {
        HStack {
            Text("程度")
                .foregroundStyle(.secondary)
            Picker("程度", selection: $level) {
                ForEach(AdjustmentLevel.allCases) { l in
                    Text(l.title).tag(l)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

/// 所有补正放在同一栏：加分类 + 舍得 + 财富 + 化妆/滤镜
struct AdjustmentsForm: View {
    @Binding var adj: Adjustments

    var body: some View {
        Group {
            bonusRows
            generosityRows
            deductionRows
        }
    }

    @ViewBuilder
    private var bonusRows: some View {
        Toggle("学历补正", isOn: $adj.education)
        Toggle("事业补正", isOn: $adj.career)

        HStack {
            Text("上镜度补正")
            Spacer()
            Picker("上镜度补正", selection: $adj.cameraLook) {
                ForEach(CameraLook.allCases) { look in
                    Text(look.title).tag(look)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 220)
        }

        Toggle("财富补正", isOn: $adj.wealth)

        Text(String(format: "学历 / 事业 / 镜度的加分强度 %.0f%%（满额 100%%）", adj.strength * 100))
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var generosityRows: some View {
        HStack {
            Text("舍得补正")
            Spacer()
            Picker("舍得补正", selection: $adj.generosity) {
                ForEach(Generosity.allCases) { g in
                    Text(g.title).tag(g)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 240)
        }

        Text("舍得：愿意为伴侣花钱；不舍得：不愿在情感中花钱")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var deductionRows: some View {
        Toggle("化妆", isOn: $adj.makeupEnabled)
        if adj.makeupEnabled {
            LevelPicker(level: $adj.makeupLevel)
        }

        Toggle("滤镜", isOn: $adj.filterEnabled)
        if adj.filterEnabled {
            LevelPicker(level: $adj.filterLevel)
        }

        Text(String(format: "化妆 / 滤镜当前扣分 −%.2f%%（最多各 −6.25%%）", (1 - adj.deductionMultiplier) * 100))
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

// MARK: - 排行榜

struct ExportedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct RankingView: View {
    @ObservedObject var viewModel: ScoreViewModel
    @State private var showDeleteAlert = false
    @State private var idsToDelete: [UUID] = []
    @State private var exported: ExportedImage?

    var body: some View {
        let ranked = viewModel.rankedPeople

        NavigationStack {
            List {
                if ranked.isEmpty {
                    Text("还没有人上榜")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, person in
                    NavigationLink {
                        PersonDetailView(viewModel: viewModel, personID: person.id)
                    } label: {
                        HStack {
                            Text("\(index + 1). \(person.name)")
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(String(format: "%.3f", person.averageScore))
                                Text("\(person.entries.count) 次评分")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    idsToDelete = offsets.map { ranked[$0].id }
                    showDeleteAlert = true
                }
            }
            .navigationTitle("排行榜")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exportImage()
                    } label: {
                        Label("导出图片", systemImage: "square.and.arrow.up")
                    }
                    .disabled(ranked.isEmpty)
                }
            }
            .alert("确认删除", isPresented: $showDeleteAlert) {
                Button("删除", role: .destructive) {
                    viewModel.removePeople(ids: idsToDelete)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("确定要删除该排位吗？该人的所有评分记录都会被删除。")
            }
            .sheet(item: $exported) { item in
                ExportPreviewView(image: item.image)
            }
        }
    }

    @MainActor
    private func exportImage() {
        let card = RankingExportCard(people: viewModel.rankedPeople, date: Date())
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let image = renderer.uiImage {
            exported = ExportedImage(image: image)
        }
    }
}

// MARK: - 个人详情（平均雷达图 + 历史）

struct PersonDetailView: View {
    @ObservedObject var viewModel: ScoreViewModel
    let personID: UUID

    var body: some View {
        if let person = viewModel.people.first(where: { $0.id == personID }) {
            List {
                Section("平均得分") {
                    Text(String(format: "%.3f（共 %d 次）", person.averageScore, person.entries.count))
                        .font(.headline)
                    if let dims = person.averageDims {
                        RadarChartView(values: dims)
                            .frame(maxWidth: .infinity)
                            .frame(height: 260)
                    } else {
                        Text("暂无各项得分数据")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("评分记录") {
                    ForEach(person.entries.sorted { $0.date > $1.date }) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                Text(entry.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%.3f", entry.score))
                        }
                    }
                    .onDelete { offsets in
                        let sorted = person.entries.sorted { $0.date > $1.date }
                        viewModel.removeEntries(ids: offsets.map { sorted[$0].id }, from: personID)
                    }
                }
            }
            .navigationTitle(person.name)
        } else {
            Text("该记录已删除")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 导出图片

/// 渲染成图片的排行榜卡片（固定宽度，高度随人数增长）
struct RankingExportCard: View {
    let people: [Person]
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("BTrank 排行榜")
                    .font(.title.bold())
                Text("\(date.formatted(date: .abbreviated, time: .omitted)) · 共 \(people.count) 人")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(rankColor(index)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name)
                            .font(.headline)
                        Text("\(person.entries.count) 次评分")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let dims = person.averageDims {
                        RadarChartView(values: dims, showLabels: false)
                            .frame(width: 64, height: 64)
                    }

                    Text(String(format: "%.2f", person.averageScore))
                        .font(.title3.bold().monospacedDigit())
                        .frame(width: 58, alignment: .trailing)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.08)))
            }
        }
        .padding(20)
        .frame(width: 390)
        .background(Color.white)
    }

    private func rankColor(_ index: Int) -> Color {
        switch index {
        case 0: return .orange
        case 1: return .gray
        case 2: return .brown
        default: return .pink.opacity(0.7)
        }
    }
}

struct ExportPreviewView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
            .navigationTitle("预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: Image(uiImage: image),
                              preview: SharePreview("BTrank 排行榜", image: Image(uiImage: image))) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

// MARK: - 工具

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
