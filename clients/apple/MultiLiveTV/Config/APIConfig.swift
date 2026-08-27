import Foundation

enum APIConfig {
    #if DEBUG
    static let baseURL = URL(string: "http://localhost:8080/api/v1")!
    #else
    static let baseURL = URL(string: "https://your-domain.example.com/api/v1")!
    #endif
}
