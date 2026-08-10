public enum AgentPromptLanguage: Sendable {
    case english
    case russian
}

public struct AgentPromptInput: Sendable {
    public let planPath: String
    public let repositoryName: String
    public let repositoryPath: String
    public let title: String
    public let nextStep: String?
    public let completedSteps: Int
    public let totalSteps: Int

    public init(
        planPath: String,
        repositoryName: String,
        repositoryPath: String,
        title: String,
        nextStep: String?,
        completedSteps: Int,
        totalSteps: Int
    ) {
        self.planPath = planPath
        self.repositoryName = repositoryName
        self.repositoryPath = repositoryPath
        self.title = title
        self.nextStep = nextStep
        self.completedSteps = completedSteps
        self.totalSteps = totalSteps
    }
}

public enum AgentPrompt {
    public static func make(
        _ input: AgentPromptInput,
        language: AgentPromptLanguage = .english
    ) -> String {
        switch language {
        case .english:
            return english(input)
        case .russian:
            return russian(input)
        }
    }

    private static func english(_ input: AgentPromptInput) -> String {
        let progress = input.totalSteps > 0
            ? "\(input.completedSteps) of \(input.totalSteps) steps complete"
            : "steps are not marked with checkboxes"
        var lines = [
            input.nextStep == nil ? "Review and finish this plan." : "Continue work on this plan.",
            "",
            "Plan: \(input.planPath)",
            "Repository: \(input.repositoryName) (\(input.repositoryPath))",
            "Progress: \(progress)",
            "Title: \(input.title)"
        ]

        if let nextStep = input.nextStep, !nextStep.isEmpty {
            lines.append("Next step: \(nextStep)")
            lines.append("")
            lines.append("Read the full plan, complete its next open step, update the checkbox in the file, and briefly report what changed.")
        } else {
            lines.append("")
            lines.append("Read the full plan, run its validation and acceptance checks, and report whether it is ready to close.")
        }

        return lines.joined(separator: "\n")
    }

    private static func russian(_ input: AgentPromptInput) -> String {
        let progress = input.totalSteps > 0
            ? "выполнено \(input.completedSteps) из \(input.totalSteps) шагов"
            : "шаги не размечены чекбоксами"
        var lines = [
            input.nextStep == nil ? "Проверь и заверши этот план." : "Продолжи работу над этим планом.",
            "",
            "План: \(input.planPath)",
            "Репозиторий: \(input.repositoryName) (\(input.repositoryPath))",
            "Прогресс: \(progress)",
            "Название: \(input.title)"
        ]

        if let nextStep = input.nextStep, !nextStep.isEmpty {
            lines.append("Следующий шаг: \(nextStep)")
            lines.append("")
            lines.append("Прочитай план целиком, выполни следующий открытый шаг, обнови чекбокс в файле и коротко сообщи, что изменилось.")
        } else {
            lines.append("")
            lines.append("Прочитай план целиком, выполни проверки и критерии приёмки и сообщи, готов ли план к закрытию.")
        }

        return lines.joined(separator: "\n")
    }
}
