enum AudioExportPresentationGate {
    static func isCommandAvailable(
        isExportInFlight: Bool,
        baseAvailability: () -> Bool
    ) -> Bool {
        guard canStart(isExportInFlight: isExportInFlight) else {
            return false
        }
        return baseAvailability()
    }

    static func canStart(isExportInFlight: Bool) -> Bool {
        !isExportInFlight
    }

    @discardableResult
    static func performIfAvailable<Result>(
        isExportInFlight: Bool,
        operation: () -> Result
    ) -> Result? {
        guard canStart(isExportInFlight: isExportInFlight) else {
            return nil
        }
        return operation()
    }

    static func endPresentation<Presentation>(
        _ presentation: Presentation?,
        close: (Presentation) -> Void
    ) -> Presentation? {
        if let presentation {
            close(presentation)
        }
        return nil
    }

}
