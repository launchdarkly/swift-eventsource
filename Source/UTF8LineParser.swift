import Foundation

struct DataIter: IteratorProtocol {
    var data: Data
    var position: Data.Index { data.startIndex }

    mutating func next() -> UInt8? {
        data.popFirst()
    }
}

class UTF8LineParser {
    private let lf = Unicode.Scalar(0x0A)
    private let cr = Unicode.Scalar(0x0D)
    private let replacement = String(Unicode.UTF8.decode(Unicode.UTF8.encodedReplacementCharacter))

    var utf8Parser = Unicode.UTF8.ForwardParser()
    var remainder: Data = Data()
    var currentString: String = ""
    var seenCr = false

    func append(_ body: Data) -> [String] {
        let data = remainder + body
        var dataIter = DataIter(data: data)
        var remainderPos = data.endIndex
        var lines: [String] = []

        Decode: while true {
            switch utf8Parser.parseScalar(from: &dataIter) {
            case .valid(let scalarResult):
                let scalar = Unicode.UTF8.decode(scalarResult)

                if seenCr && scalar == lf {
                    seenCr = false
                    continue
                }

                seenCr = scalar == cr
                if scalar == cr || scalar == lf {
                    lines.append(currentString)
                    currentString = ""
                } else {
                    currentString.append(String(scalar))
                }
            case .emptyInput:
                break Decode
            case .error(let len):
                seenCr = false
                if dataIter.position == data.endIndex {
                    // Error at end of block, carry over in case of split code point
                    remainderPos = data.index(data.endIndex, offsetBy: -len)
                    // May as well break here as next will be .emptyInput
                    break Decode
                } else {
                    // Invalid character, replace with replacement character
                    currentString.append(replacement)
                }
            }
        }

        remainder = data.subdata(in: remainderPos..<data.endIndex)
        return lines
    }

    func closeAndReset() {
        seenCr = false
        currentString = ""
        remainder = Data()
    }
}
