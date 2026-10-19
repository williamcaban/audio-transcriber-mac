enum BackendLoadState: Equatable {
    case notLoaded
    case loading(progress: Double, message: String)
    case ready
    case failed(String)
}
