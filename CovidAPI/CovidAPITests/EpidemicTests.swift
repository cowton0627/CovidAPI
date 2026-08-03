import XCTest
@testable import CovidAPI

final class EpidemicTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    func testAlertLevelUsesHighestMatchingLevel() {
        let epidemic = Epidemic(
            headline: "測試地區 第一級注意",
            effective: date,
            description: "最新調整為第三級警告"
        )

        XCTAssertEqual(AlertLevel.from(epidemic: epidemic), .warning)
    }

    func testRepositorySavesFreshResponse() {
        let item = makeEpidemic(headline: "日本 第二級警示")
        let cache = CacheStub()
        let repository = EpidemicRepository(
            apiClient: APIClientStub(result: .success([item])),
            cache: cache
        )
        let expectation = expectation(description: "refresh")

        repository.refresh { result in
            guard case .success(let snapshot) = result else {
                return XCTFail("Expected a successful snapshot")
            }
            XCTAssertEqual(snapshot.epidemics, [item])
            XCTAssertFalse(snapshot.isFromCache)
            XCTAssertEqual(cache.saved, [item])
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testRepositoryFallsBackToCacheWhenNetworkFails() {
        let cached = makeEpidemic(headline: "離線資料")
        let cache = CacheStub(loaded: [cached])
        let repository = EpidemicRepository(
            apiClient: APIClientStub(result: .failure(TestError.offline)),
            cache: cache
        )
        let expectation = expectation(description: "cached fallback")

        repository.refresh { result in
            guard case .success(let snapshot) = result else {
                return XCTFail("Expected cached data")
            }
            XCTAssertEqual(snapshot.epidemics, [cached])
            XCTAssertTrue(snapshot.isFromCache)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testRepositoryMarksInMemoryFallbackAsCached() {
        let item = makeEpidemic(headline: "最新資料")
        let apiClient = SequenceAPIClientStub(results: [
            .success([item]),
            .failure(TestError.offline)
        ])
        let repository = EpidemicRepository(apiClient: apiClient, cache: CacheStub())
        let freshExpectation = expectation(description: "fresh response")
        let fallbackExpectation = expectation(description: "in-memory fallback")

        repository.refresh { firstResult in
            guard case .success(let freshSnapshot) = firstResult else {
                return XCTFail("Expected a fresh snapshot")
            }
            XCTAssertFalse(freshSnapshot.isFromCache)
            freshExpectation.fulfill()

            repository.refresh { secondResult in
                guard case .success(let fallbackSnapshot) = secondResult else {
                    return XCTFail("Expected an in-memory fallback")
                }
                XCTAssertEqual(fallbackSnapshot.epidemics, [item])
                XCTAssertTrue(fallbackSnapshot.isFromCache)
                fallbackExpectation.fulfill()
            }
        }

        wait(for: [freshExpectation, fallbackExpectation], timeout: 1)
    }

    func testViewModelSearchAndLevelFilter() {
        let warning = makeEpidemic(headline: "日本 第三級警告")
        let watch = makeEpidemic(headline: "泰國 第一級注意")
        let repository = EpidemicRepository(
            apiClient: APIClientStub(result: .success([warning, watch])),
            cache: CacheStub()
        )
        let viewModel = EpidemicListViewModel(repository: repository)
        let expectation = expectation(description: "loaded")
        var didFulfill = false

        viewModel.onChange = {
            if viewModel.allEpidemics.count == 2, !didFulfill {
                didFulfill = true
                expectation.fulfill()
            }
        }
        viewModel.load()
        wait(for: [expectation], timeout: 1)

        viewModel.setSearchQuery("泰國")
        XCTAssertEqual(viewModel.visibleEpidemics, [watch])

        viewModel.setSearchQuery("")
        viewModel.setFilter(.warning)
        XCTAssertEqual(viewModel.visibleEpidemics, [warning])
    }

    private func makeEpidemic(headline: String) -> Epidemic {
        Epidemic(headline: headline, effective: date, description: "測試內容")
    }
}

private enum TestError: Error {
    case offline
}

private final class APIClientStub: EpidemicAPIClientProtocol {
    let result: Result<[Epidemic], Error>

    init(result: Result<[Epidemic], Error>) {
        self.result = result
    }

    func fetch(completion: @escaping (Result<[Epidemic], Error>) -> Void) {
        completion(result)
    }
}

private final class SequenceAPIClientStub: EpidemicAPIClientProtocol {
    private var results: [Result<[Epidemic], Error>]

    init(results: [Result<[Epidemic], Error>]) {
        self.results = results
    }

    func fetch(completion: @escaping (Result<[Epidemic], Error>) -> Void) {
        completion(results.removeFirst())
    }
}

private final class CacheStub: EpidemicCacheProtocol {
    let loaded: [Epidemic]?
    var saved: [Epidemic]?
    var modifiedAt: Date? = Date(timeIntervalSince1970: 1_700_000_000)

    init(loaded: [Epidemic]? = nil) {
        self.loaded = loaded
    }

    func load() -> [Epidemic]? {
        loaded
    }

    func save(_ epidemics: [Epidemic]) {
        saved = epidemics
    }
}
