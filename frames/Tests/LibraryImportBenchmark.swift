import Foundation

@MainActor
enum LibraryImportBenchmark {
    struct Sample: Codable {
        let limit: Int
        let thumbnails: Bool
        let warmCache: Bool
        let wallSeconds: Double
        let maxStallMs: Double
    }

    struct Summary: Codable {
        let limit: Int
        let thumbnails: Bool
        let warmCache: Bool
        let medianWallSeconds: Double
        let maxStallMs: Double
    }

    struct Report: Codable {
        let directory: String
        let fileCount: Int
        let processorCount: Int
        let repeats: Int
        let baselineLimit: Int
        let chosenLimit: Int
        let summaries: [Summary]
    }

    static let heartbeatInterval: TimeInterval = 0.010
    static let requiredSpeedup = 0.20
    static let stallBudgetMs = 100.0

    static var limits: [Int] {
        var seen = Set<Int>()
        return [1, 2, 4, ProcessInfo.processInfo.activeProcessorCount].filter { seen.insert($0).inserted }
    }

    static let defaultDocument = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("docs/benchmarks/library-import-concurrency.md")

    static func runFromCommandLine(_ arguments: [String]) -> Never {
        var isDir: ObjCBool = false
        guard let path = arguments.first, !path.hasPrefix("-"),
              FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue
        else {
            print("usage: frames --benchmark-import <dir> [--repeats N] [--output <file.md>]")
            exit(2)
        }
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        let repeats = value(after: "--repeats").flatMap(Int.init) ?? 3
        let output = value(after: "--output").map { URL(fileURLWithPath: $0) } ?? defaultDocument

        let report = run(directory: URL(fileURLWithPath: path), repeats: max(1, repeats))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let json = try? encoder.encode(report), let text = String(data: json, encoding: .utf8) {
            print(text)
        }
        do {
            try FileManager.default.createDirectory(
                at: output.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try markdown(report).write(to: output, atomically: true, encoding: .utf8)
            print("wrote \(output.path)")
        } catch {
            print("failed to write \(output.path): \(error)")
            fflush(stdout)
            exit(1)
        }
        fflush(stdout)
        exit(0)
    }

    static func run(directory: URL, repeats: Int = 3) -> Report {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("frames-import-benchmark-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        _ = importOnce(directory: directory, limit: LibraryManager.defaultMetadataConcurrency, thumbnails: true,
                       cacheDirectory: root.appendingPathComponent("warmup", isDirectory: true))

        var samples: [Sample] = []
        var fileCount = 0
        for repeatIndex in 0 ..< repeats {
            for thumbnails in [false, true] {
                for limit in limits {
                    let cacheName = "r\(repeatIndex)-t\(thumbnails)-l\(limit)"
                    let cacheDir = root.appendingPathComponent(cacheName, isDirectory: true)
                    for warm in [false, true] {
                        let (sample, count) = importOnce(directory: directory, limit: limit, thumbnails: thumbnails,
                                                         cacheDirectory: cacheDir, warmCache: warm)
                        samples.append(sample)
                        fileCount = count
                    }
                }
            }
        }

        let summaries = summarize(samples)
        return Report(
            directory: directory.path,
            fileCount: fileCount,
            processorCount: ProcessInfo.processInfo.activeProcessorCount,
            repeats: repeats,
            baselineLimit: 2,
            chosenLimit: chooseLimit(summaries),
            summaries: summaries
        )
    }

    private static func importOnce(directory: URL, limit: Int, thumbnails: Bool,
                                   cacheDirectory: URL, warmCache: Bool = false) -> (Sample, Int)
    {
        let defaults = LibraryMetadataTests.scratchDefaults(in: cacheDirectory.deletingLastPathComponent()) ?? .standard

        var config = LibraryConfiguration()
        config.defaults = defaults
        config.cache = LibraryCache(directory: cacheDirectory)
        config.metadataConcurrency = limit
        config.includeThumbnails = thumbnails
        config.observesFileSystem = false
        let lib = LibraryManager(configuration: config)

        let heartbeat = Heartbeat()
        let timer = Timer(timeInterval: heartbeatInterval, repeats: true) { _ in
            MainActor.assumeIsolated { heartbeat.beat() }
        }
        RunLoop.main.add(timer, forMode: .common)

        let start = CFAbsoluteTimeGetCurrent()
        heartbeat.lastBeat = start
        lib.addFolder(url: directory)
        while lib.isScanning || lib.pendingMetadataLoads > 0 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(heartbeatInterval))
        }
        let wall = CFAbsoluteTimeGetCurrent() - start
        timer.invalidate()
        heartbeat.beat()

        let stallMs = max(0, (heartbeat.maxGap - heartbeatInterval) * 1000)
        let sample = Sample(limit: limit, thumbnails: thumbnails, warmCache: warmCache,
                            wallSeconds: wall, maxStallMs: stallMs)
        return (sample, lib.videos.count)
    }

    @MainActor
    private final class Heartbeat {
        var lastBeat = CFAbsoluteTimeGetCurrent()
        var maxGap = 0.0

        func beat() {
            let now = CFAbsoluteTimeGetCurrent()
            maxGap = max(maxGap, now - lastBeat)
            lastBeat = now
        }
    }

    private static func summarize(_ samples: [Sample]) -> [Summary] {
        var summaries: [Summary] = []
        for thumbnails in [false, true] {
            for warm in [false, true] {
                for limit in limits {
                    let group = samples.filter {
                        $0.limit == limit && $0.thumbnails == thumbnails && $0.warmCache == warm
                    }
                    guard !group.isEmpty else { continue }
                    let walls = group.map(\.wallSeconds).sorted()
                    summaries.append(Summary(
                        limit: limit,
                        thumbnails: thumbnails,
                        warmCache: warm,
                        medianWallSeconds: walls[walls.count / 2],
                        maxStallMs: group.map(\.maxStallMs).max() ?? 0
                    ))
                }
            }
        }
        return summaries
    }

    static func chooseLimit(_ summaries: [Summary], baseline: Int = 2) -> Int {
        func cold(_ limit: Int, thumbnails: Bool) -> Summary? {
            summaries.first { $0.limit == limit && $0.thumbnails == thumbnails && !$0.warmCache }
        }
        var best = baseline
        var bestWall = cold(baseline, thumbnails: true)?.medianWallSeconds ?? .infinity
        for limit in Set(summaries.map(\.limit)) where limit > baseline {
            let qualifies = [false, true].allSatisfy { thumbnails in
                guard let candidate = cold(limit, thumbnails: thumbnails),
                      let base = cold(baseline, thumbnails: thumbnails) else { return false }
                return candidate.medianWallSeconds <= base.medianWallSeconds * (1 - requiredSpeedup)
            }
            let stalls = summaries.filter { $0.limit == limit }.allSatisfy { $0.maxStallMs <= stallBudgetMs }
            guard qualifies, stalls,
                  let wall = cold(limit, thumbnails: true)?.medianWallSeconds,
                  wall < bestWall else { continue }
            best = limit
            bestWall = wall
        }
        return best
    }

    static func markdown(_ report: Report) -> String {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let rulePercent = Int(requiredSpeedup * 100)
        let baseline = report.baselineLimit
        var lines = [
            "# Library import concurrency benchmark",
            "",
            "Generated by `frames --benchmark-import \(report.directory)` "
                + "(\(report.fileCount) files, \(report.processorCount) cores, macOS \(osVersion)).",
            "Each configuration ran \(report.repeats) times through `LibraryManager.addFolder` with a temp cache "
                + "and a temp `UserDefaults` suite.",
            "The table shows the median wall time and the longest main-thread stall across repeats.",
            "",
            "\"Cold\" means the app's library cache is empty.",
            "One untimed warm-up pass primes the OS file cache first, so disk reads are not cold.",
            "The stall is the longest gap between 10 ms main-thread heartbeats, minus 10 ms.",
            "",
            "| Mode | Cache | Limit | Median wall (s) | Max stall (ms) |",
            "| --- | --- | --- | --- | --- |",
        ]
        for summary in report.summaries {
            let mode = summary.thumbnails ? "metadata + thumbnail" : "metadata only"
            let cache = summary.warmCache ? "warm" : "cold"
            let wall = String(format: "%.3f", summary.medianWallSeconds)
            let stall = String(format: "%.1f", summary.maxStallMs)
            lines.append("| \(mode) | \(cache) | \(summary.limit) | \(wall) | \(stall) |")
        }
        let perCore = report.chosenLimit == report.processorCount
        let decision: String
        if report.chosenLimit == baseline {
            decision = "No limit met the rule, so the gate stays at \(baseline)."
        } else if perCore {
            decision = "Limit \(report.chosenLimit) (one per core) met the rule, so "
                + "`LibraryManager.defaultMetadataConcurrency` is `ProcessInfo.activeProcessorCount`."
        } else {
            decision = "Limit \(report.chosenLimit) met the rule, so the gate is raised to \(report.chosenLimit)."
        }
        lines += [
            "",
            "## Decision",
            "",
            "Rule: raise the limit only if a candidate's cold-cache median is at least \(rulePercent)% faster than "
                + "limit \(baseline) in both modes, with no main-thread stall over \(Int(stallBudgetMs)) ms in any "
                + "configuration.",
            "Among qualifying limits, the fastest cold metadata + thumbnail median wins.",
            "",
            perCore ? decision : decision + " `LibraryManager.defaultMetadataConcurrency` is \(report.chosenLimit).",
            "",
        ]
        return lines.joined(separator: "\n")
    }
}
