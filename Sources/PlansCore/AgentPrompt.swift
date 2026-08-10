public enum AgentPromptLanguage: Sendable {
    case english
    case russian
}

public enum AgentPromptIntent: Sendable, Equatable {
    case continuePlan
    case closePlan
    case activatePlan
}

public struct AgentPromptInput: Sendable {
    public let planPath: String
    public let repositoryName: String
    public let repositoryPath: String
    public let title: String
    public let nextStep: String?
    public let completedSteps: Int
    public let totalSteps: Int
    public let intent: AgentPromptIntent

    public init(
        planPath: String,
        repositoryName: String,
        repositoryPath: String,
        title: String,
        nextStep: String?,
        completedSteps: Int,
        totalSteps: Int,
        intent: AgentPromptIntent? = nil
    ) {
        self.planPath = planPath
        self.repositoryName = repositoryName
        self.repositoryPath = repositoryPath
        self.title = title
        self.nextStep = nextStep
        self.completedSteps = completedSteps
        self.totalSteps = totalSteps
        self.intent = intent ?? (nextStep == nil ? .closePlan : .continuePlan)
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
            englishTitle(input.intent),
            "",
            "Plan: \(input.planPath)",
            "Repository: \(input.repositoryName) (\(input.repositoryPath))",
            "Progress: \(progress)",
            "Title: \(input.title)"
        ]

        if input.intent == .closePlan {
            lines.append("")
            lines.append("Read the full plan, run its validation and acceptance checks, then close it according to the repository instructions if the evidence is complete.")
        } else if let nextStep = input.nextStep, !nextStep.isEmpty {
            lines.append("Next step: \(nextStep)")
            lines.append("")
            let instruction = input.intent == .activatePlan
                ? "Read the full plan, activate it according to the repository instructions, complete its first open step, update the file, and briefly report what changed."
                : "Read the full plan, complete its next open step, update the checkbox in the file, and briefly report what changed."
            lines.append(instruction)
        } else {
            lines.append("")
            lines.append("Read the full plan and report the next safe action.")
        }

        return lines.joined(separator: "\n")
    }

    private static func russian(_ input: AgentPromptInput) -> String {
        let progress = input.totalSteps > 0
            ? "выполнено \(input.completedSteps) из \(input.totalSteps) шагов"
            : "шаги не размечены чекбоксами"
        var lines = [
            russianTitle(input.intent),
            "",
            "План: \(input.planPath)",
            "Репозиторий: \(input.repositoryName) (\(input.repositoryPath))",
            "Прогресс: \(progress)",
            "Название: \(input.title)"
        ]

        if input.intent == .closePlan {
            lines.append("")
            lines.append("Прочитай план целиком, выполни проверки и критерии приёмки, затем закрой его по правилам репозитория, если все результаты подтверждены.")
        } else if let nextStep = input.nextStep, !nextStep.isEmpty {
            lines.append("Следующий шаг: \(nextStep)")
            lines.append("")
            let instruction = input.intent == .activatePlan
                ? "Прочитай план целиком, активируй его по правилам репозитория, выполни первый открытый шаг, обнови файл и коротко сообщи, что изменилось."
                : "Прочитай план целиком, выполни следующий открытый шаг, обнови чекбокс в файле и коротко сообщи, что изменилось."
            lines.append(instruction)
        } else {
            lines.append("")
            lines.append("Прочитай план целиком и сообщи следующее безопасное действие.")
        }

        return lines.joined(separator: "\n")
    }

    private static func englishTitle(_ intent: AgentPromptIntent) -> String {
        switch intent {
        case .continuePlan: return "Continue work on this plan."
        case .closePlan: return "Review and finish this plan."
        case .activatePlan: return "Activate and start this plan."
        }
    }

    private static func russianTitle(_ intent: AgentPromptIntent) -> String {
        switch intent {
        case .continuePlan: return "Продолжи работу над этим планом."
        case .closePlan: return "Проверь и заверши этот план."
        case .activatePlan: return "Активируй и начни этот план."
        }
    }
}
