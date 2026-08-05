public enum TranscriptionArgs {
    public static func buildArguments(
        modelPath: String,
        inputWAVPath: String,
        outputBasePath: String
    ) -> [String] {
        [
            "-m", modelPath,
            "-f", inputWAVPath,
            "-of", outputBasePath,
            "-otxt",
            "-nt"
        ]
    }
}
