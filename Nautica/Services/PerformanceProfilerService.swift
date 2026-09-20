import Foundation
import MachO
import Darwin

/// Benchmark result containing execution latency, memory delta, and throughput.
public struct BenchmarkMetric<T> {
    public let label: String
    public let result: T
    public let durationSeconds: Double
    public let startMemoryBytes: UInt64
    public let endMemoryBytes: UInt64
    public let memoryDeltaBytes: Int64
    public let itemCount: Int

    public var durationMs: Double {
        durationSeconds * 1000.0
    }

    public var itemsPerSecond: Double {
        guard durationSeconds > 0 else { return 0 }
        return Double(itemCount) / durationSeconds
    }
}

/// Comprehensive benchmark report for large directory stress tests.
public struct DirectoryStressReport {
    public let itemCount: Int
    public let generationDurationSeconds: Double
    public let enumerationDurationSeconds: Double
    public let sortByNameDurationSeconds: Double
    public let sortBySizeDurationSeconds: Double
    public let sortByDateDurationSeconds: Double
    public let filterDurationSeconds: Double
    public let startMemoryBytes: UInt64
    public let peakMemoryBytes: UInt64
    public let memoryDeltaBytes: Int64

    public var summary: String {
        String(
            format: "[%d Items] Enum: %.2f ms (%.0f items/s) | Sort: %.2f ms | Filter: %.2f ms | Memory Delta: %.2f MB",
            itemCount,
            enumerationDurationSeconds * 1000.0,
            Double(itemCount) / max(0.0001, enumerationDurationSeconds),
            sortByNameDurationSeconds * 1000.0,
            filterDurationSeconds * 1000.0,
            Double(memoryDeltaBytes) / (1024.0 * 1024.0)
        )
    }
}

/// High-performance profiling and stress testing service.
public final class PerformanceProfilerService {
    public static let shared = PerformanceProfilerService()

    private init() {}

    /// Returns the current process resident set size (physical RAM) in bytes.
    public var currentResidentMemoryBytes: UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kerr == KERN_SUCCESS ? info.resident_size : 0
    }

    /// Measures the execution time and memory delta of a synchronous block.
    public func measure<T>(
        label: String,
        itemCount: Int = 1,
        operation: () throws -> T
    ) rethrows -> BenchmarkMetric<T> {
        let memStart = currentResidentMemoryBytes
        let timeStart = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)

        let result = try operation()

        let timeEnd = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let memEnd = currentResidentMemoryBytes

        let durationSeconds = Double(timeEnd - timeStart) / 1_000_000_000.0
        let memDelta = Int64(memEnd) - Int64(memStart)

        return BenchmarkMetric(
            label: label,
            result: result,
            durationSeconds: durationSeconds,
            startMemoryBytes: memStart,
            endMemoryBytes: memEnd,
            memoryDeltaBytes: memDelta,
            itemCount: itemCount
        )
    }

    /// Measures the execution time and memory delta of an asynchronous block.
    public func measureAsync<T>(
        label: String,
        itemCount: Int = 1,
        operation: () async throws -> T
    ) async rethrows -> BenchmarkMetric<T> {
        let memStart = currentResidentMemoryBytes
        let timeStart = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)

        let result = try await operation()

        let timeEnd = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let memEnd = currentResidentMemoryBytes

        let durationSeconds = Double(timeEnd - timeStart) / 1_000_000_000.0
        let memDelta = Int64(memEnd) - Int64(memStart)

        return BenchmarkMetric(
            label: label,
            result: result,
            durationSeconds: durationSeconds,
            startMemoryBytes: memStart,
            endMemoryBytes: memEnd,
            memoryDeltaBytes: memDelta,
            itemCount: itemCount
        )
    }

    /// High-performance synthetic directory generator.
    /// Creates realistic directory trees rapidly using POSIX system calls.
    public func createSyntheticDirectory(
        at targetURL: URL,
        count: Int,
        subfolderRatio: Double = 0.05
    ) throws {
        if !FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        }

        let extensions = ["txt", "png", "pdf", "swift", "json", "jpg", "md", "zip", "csv", "xml"]
        let subfolderCount = Int(Double(count) * subfolderRatio)
        let fileCount = count - subfolderCount

        // Create subdirectories
        for i in 0..<subfolderCount {
            let folderURL = targetURL.appendingPathComponent(String(format: "Folder_%04d", i), isDirectory: true)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }

        let contentPayload = "Nautica high-performance benchmarking test file payload content.\n"
        let payloadData = contentPayload.data(using: .utf8)!

        // Generate files
        for i in 0..<fileCount {
            let ext = extensions[i % extensions.count]
            let filename = String(format: "Item_%06d.%@", i, ext)
            let destinationURL = targetURL.appendingPathComponent(filename)

            let path = destinationURL.path(percentEncoded: false)
            let fd = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
            if fd >= 0 {
                _ = payloadData.withUnsafeBytes { ptr in
                    write(fd, ptr.baseAddress, ptr.count)
                }
                close(fd)
            }
        }
    }
}
