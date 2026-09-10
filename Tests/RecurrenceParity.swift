import Foundation

@main enum RecurrenceParity {
    struct Input: Decodable { let events: [CalEvent]; let from: String; let through: String }
    static func main() throws {
        let input = try JSONDecoder().decode(Input.self, from: FileHandle.standardInput.readDataToEndOfFile())
        let output = DeadlineSchedule.expand(input.events, from: input.from, through: input.through)
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
