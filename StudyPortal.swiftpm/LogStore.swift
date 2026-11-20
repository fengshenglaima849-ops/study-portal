import Foundation

/// 1回分の勉強の記録
struct StudyLog: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date
    var seconds: Int
    var book: String
    var place: String

    var minutes: Int { seconds / 60 }
}

/// 1日ぶんの合計
struct DayTotal: Identifiable {
    let day: Date
    let seconds: Int
    var id: Date { day }
}

/// 参考書・場所ごとの合計
struct NamedTotal: Identifiable {
    let name: String
    let seconds: Int
    var id: String { name }
}

/// 勉強の記録と、試験・参考書・場所の設定。変更するとその場で端末に保存する
@MainActor
final class LogStore: ObservableObject {
    /// 新しい順
    @Published private(set) var logs: [StudyLog] = []

    @Published var examName: String { didSet { UserDefaults.standard.set(examName, forKey: "examName") } }
    @Published var examDate: Date { didSet { UserDefaults.standard.set(examDate, forKey: "examDate") } }
    @Published var books: [String] { didSet { UserDefaults.standard.set(books, forKey: "books") } }
    @Published var places: [String] { didSet { UserDefaults.standard.set(places, forKey: "places") } }
    /// 次の記録に付ける参考書と場所（空なら未選択）
    @Published var selectedBook: String { didSet { UserDefaults.standard.set(selectedBook, forKey: "selectedBook") } }
    @Published var selectedPlace: String { didSet { UserDefaults.standard.set(selectedPlace, forKey: "selectedPlace") } }

    init() {
        let d = UserDefaults.standard
        examName = d.string(forKey: "examName") ?? "試験"
        examDate = d.object(forKey: "examDate") as? Date
            ?? Calendar.current.date(byAdding: .day, value: 90, to: Date()) ?? Date()
        books = d.stringArray(forKey: "books") ?? ["Chapter 6", "Chapter 7", "Chapter 8"]
        places = d.stringArray(forKey: "places") ?? ["自宅", "chocoZAP"]
        selectedBook = d.string(forKey: "selectedBook") ?? ""
        selectedPlace = d.string(forKey: "selectedPlace") ?? ""
        logs = Self.loadLogs()
    }

    // MARK: - 記録

    func add(date: Date, seconds: Int) {
        guard seconds >= 60 else { return }
        logs.insert(StudyLog(date: date, seconds: seconds, book: selectedBook, place: selectedPlace), at: 0)
        sortAndSave()
    }

    func update(_ log: StudyLog) {
        guard let i = logs.firstIndex(where: { $0.id == log.id }) else { return }
        logs[i] = log
        sortAndSave()
    }

    func delete(_ ids: [UUID]) {
        logs.removeAll { ids.contains($0.id) }
        sortAndSave()
    }

    // MARK: - 参考書・場所

    func addBook(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !books.contains(n) else { return }
        books.append(n)
    }

    func removeBooks(at offsets: IndexSet) {
        let removed = offsets.map { books[$0] }
        books.remove(atOffsets: offsets)
        if removed.contains(selectedBook) { selectedBook = "" }
    }

    func addPlace(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !places.contains(n) else { return }
        places.append(n)
    }

    func removePlaces(at offsets: IndexSet) {
        let removed = offsets.map { places[$0] }
        places.remove(atOffsets: offsets)
        if removed.contains(selectedPlace) { selectedPlace = "" }
    }

    // MARK: - 集計

    var totalSeconds: Int { logs.reduce(0) { $0 + $1.seconds } }

    /// 試験日までの日数（過ぎていれば0）
    var daysLeft: Int {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: examDate)).day ?? 0
        return max(0, days)
    }

    /// 今日を含む過去7日間の、1日ごとの合計秒数（古い順）
    func lastSevenDays(from now: Date = Date()) -> [DayTotal] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        return (0..<7).reversed().compactMap { back in
            guard let day = cal.date(byAdding: .day, value: -back, to: today) else { return nil }
            let total = logs.filter { cal.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.seconds }
            return DayTotal(day: day, seconds: total)
        }
    }

    /// 参考書ごと・場所ごとの合計秒数（多い順）
    func totals(by key: (StudyLog) -> String) -> [NamedTotal] {
        var map: [String: Int] = [:]
        for log in logs {
            let k = key(log)
            map[k.isEmpty ? "未選択" : k, default: 0] += log.seconds
        }
        return map.map { NamedTotal(name: $0.key, seconds: $0.value) }.sorted { $0.seconds > $1.seconds }
    }

    static func format(_ seconds: Int) -> String {
        let m = seconds / 60
        if m < 60 { return "\(m)分" }
        return m % 60 == 0 ? "\(m / 60)時間" : "\(m / 60)時間\(m % 60)分"
    }

    // MARK: - 保存

    private static var fileURL: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent("study-logs.json")
    }

    private static func loadLogs() -> [StudyLog] {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([StudyLog].self, from: data) else { return [] }
        return list.sorted { $0.date > $1.date }
    }

    private func sortAndSave() {
        logs.sort { $0.date > $1.date }
        guard let url = Self.fileURL, let data = try? JSONEncoder().encode(logs) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
