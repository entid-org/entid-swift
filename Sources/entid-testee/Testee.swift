import EntIDTestee
import EntIDWire
import Foundation

/// The conformance testee: reads requests on standard input, calls the public
/// API, writes responses on standard output.
///
/// Each message is preceded by its length as a 32 bit unsigned integer in
/// little endian byte order. The exchange is strictly synchronous — one request
/// in, one response out — which keeps this to a read-answer loop with no
/// buffering concern and no risk of both sides blocking on a full pipe.
@main
struct Testee {
    static func main() {
        let input = FileHandle.standardInput
        let output = FileHandle.standardOutput

        while let payload = readFrame(input) {
            let response: Entid_Testee_V1_TesteeResponse
            do {
                response = TesteeCore.respond(
                    to: try Entid_Testee_V1_TesteeRequest(serializedBytes: payload)
                )
            } catch {
                // A request that does not decode is a broken exchange, not a
                // conformance answer. Stopping is louder than guessing.
                FileHandle.standardError.write(Data("entid-testee: bad request frame\n".utf8))
                exit(2)
            }
            guard let encoded = try? response.serializedBytes() as [UInt8] else { exit(2) }
            writeFrame(output, encoded)
        }
    }

    static func readFrame(_ handle: FileHandle) -> [UInt8]? {
        guard let header = read(handle, exactly: 4) else { return nil }
        let length =
            UInt32(header[0]) | UInt32(header[1]) << 8 | UInt32(header[2]) << 16
            | UInt32(header[3]) << 24
        guard length > 0 else { return [] }
        return read(handle, exactly: Int(length))
    }

    static func read(_ handle: FileHandle, exactly count: Int) -> [UInt8]? {
        var buffer: [UInt8] = []
        buffer.reserveCapacity(count)
        while buffer.count < count {
            guard let chunk = try? handle.read(upToCount: count - buffer.count), !chunk.isEmpty else {
                return nil
            }
            buffer.append(contentsOf: chunk)
        }
        return buffer
    }

    static func writeFrame(_ handle: FileHandle, _ payload: [UInt8]) {
        let length = UInt32(payload.count)
        let header: [UInt8] = [
            UInt8(truncatingIfNeeded: length),
            UInt8(truncatingIfNeeded: length >> 8),
            UInt8(truncatingIfNeeded: length >> 16),
            UInt8(truncatingIfNeeded: length >> 24),
        ]
        handle.write(Data(header + payload))
    }
}
