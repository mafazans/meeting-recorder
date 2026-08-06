public enum TranscriptionArgs {
    public static func buildArguments(
        modelPath: String,
        inputWAVPath: String,
        outputBasePath: String,
        language: String? = nil
    ) -> [String] {
        var args = [
            "-m", modelPath,
            "-f", inputWAVPath,
            "-of", outputBasePath,
            "-otxt",
            "-nt",
            "-mc", "0"
        ]
        if let language {
            args.append(contentsOf: ["-l", language])
        }
        return args
    }
}
