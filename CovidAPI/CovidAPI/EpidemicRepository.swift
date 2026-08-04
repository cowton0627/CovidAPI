import Foundation

enum EpidemicRepositoryError: LocalizedError {
    case invalidResponse
    case emptyData
    case decodingFailed(Error)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "伺服器回應異常，請稍後再試。"
        case .emptyData:
            return "目前沒有可顯示的旅遊疫情資料。"
        case .decodingFailed:
            return "資料格式已變更，暫時無法讀取。"
        case .network:
            return "無法連上疾管署，請檢查網路後重試。"
        }
    }
}

protocol EpidemicAPIClientProtocol {
    func fetch(completion: @escaping (Result<[Epidemic], Error>) -> Void)
}

final class EpidemicAPIClient: EpidemicAPIClientProtocol {
    private let session: URLSession
    private let endpoint: URL

    init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://www.cdc.gov.tw/TravelEpidemic/ExportJSON")!
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    func fetch(completion: @escaping (Result<[Epidemic], Error>) -> Void) {
        session.dataTask(with: endpoint) { data, response, error in
            if let error = error {
                completion(.failure(EpidemicRepositoryError.network(error)))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                completion(.failure(EpidemicRepositoryError.invalidResponse))
                return
            }
            guard let data = data else {
                completion(.failure(EpidemicRepositoryError.emptyData))
                return
            }

            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                completion(.success(try decoder.decode([Epidemic].self, from: data)))
            } catch {
                completion(.failure(EpidemicRepositoryError.decodingFailed(error)))
            }
        }.resume()
    }
}

protocol EpidemicCacheProtocol {
    func load() -> [Epidemic]?
    func save(_ epidemics: [Epidemic])
    var modifiedAt: Date? { get }
}

final class EpidemicDiskCache: EpidemicCacheProtocol {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        if let fileURL = fileURL {
            self.fileURL = fileURL
        } else {
            let directory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            self.fileURL = directory.appendingPathComponent("epidemics.json")
        }
    }

    func load() -> [Epidemic]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([Epidemic].self, from: data)
    }

    func save(_ epidemics: [Epidemic]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(epidemics) else { return }
        try? fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    var modifiedAt: Date? {
        let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
        return attributes?[.modificationDate] as? Date
    }
}

struct EpidemicSnapshot {
    let epidemics: [Epidemic]
    let updatedAt: Date
    let isFromCache: Bool
}

final class EpidemicRepository {
    static let shared: EpidemicRepository = {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else {
            return EpidemicRepository()
        }
        return EpidemicRepository(apiClient: UITestingAPIClient(), cache: UITestingCache())
    }()

    private let apiClient: EpidemicAPIClientProtocol
    private let cache: EpidemicCacheProtocol
    private let queue = DispatchQueue(label: "EpidemicRepository.state")
    private var currentSnapshot: EpidemicSnapshot?
    private var isFetching = false
    private var pendingCompletions: [(Result<EpidemicSnapshot, Error>) -> Void] = []

    init(
        apiClient: EpidemicAPIClientProtocol = EpidemicAPIClient(),
        cache: EpidemicCacheProtocol = EpidemicDiskCache()
    ) {
        self.apiClient = apiClient
        self.cache = cache
        if let cached = cache.load(), !cached.isEmpty {
            currentSnapshot = EpidemicSnapshot(
                epidemics: cached,
                updatedAt: cache.modifiedAt ?? Date(),
                isFromCache: true
            )
        }
    }

    func cachedSnapshot() -> EpidemicSnapshot? {
        queue.sync { currentSnapshot }
    }

    func refresh(completion: @escaping (Result<EpidemicSnapshot, Error>) -> Void) {
        queue.async {
            self.pendingCompletions.append(completion)
            guard !self.isFetching else { return }
            self.isFetching = true

            self.apiClient.fetch { result in
                self.queue.async {
                    let finalResult: Result<EpidemicSnapshot, Error>
                    switch result {
                    case .success(let epidemics) where !epidemics.isEmpty:
                        self.cache.save(epidemics)
                        let snapshot = EpidemicSnapshot(
                            epidemics: epidemics,
                            updatedAt: Date(),
                            isFromCache: false
                        )
                        self.currentSnapshot = snapshot
                        finalResult = .success(snapshot)
                    case .success:
                        finalResult = .failure(EpidemicRepositoryError.emptyData)
                    case .failure(let error):
                        if let snapshot = self.currentSnapshot {
                            let fallback = EpidemicSnapshot(
                                epidemics: snapshot.epidemics,
                                updatedAt: snapshot.updatedAt,
                                isFromCache: true
                            )
                            self.currentSnapshot = fallback
                            finalResult = .success(fallback)
                        } else {
                            finalResult = .failure(error)
                        }
                    }

                    let completions = self.pendingCompletions
                    self.pendingCompletions.removeAll()
                    self.isFetching = false
                    DispatchQueue.main.async {
                        completions.forEach { $0(finalResult) }
                    }
                }
            }
        }
    }
}

private final class UITestingAPIClient: EpidemicAPIClientProtocol {
    func fetch(completion: @escaping (Result<[Epidemic], Error>) -> Void) {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        completion(.success([
            Epidemic(headline: "日本-腸病毒", effective: date, description: "日本疫情測試資料", areaDescription: "日本"),
            Epidemic(headline: "美國-沙門氏菌感染症", effective: date, description: "美國疫情測試資料", severityLevel: 3, areaDescription: "美國")
        ]))
    }
}

private final class UITestingCache: EpidemicCacheProtocol {
    var modifiedAt: Date? { nil }
    func load() -> [Epidemic]? { nil }
    func save(_ epidemics: [Epidemic]) {}
}
