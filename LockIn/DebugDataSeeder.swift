import Foundation

#if DEBUG
    /// Generates synthetic Steps / Gym / LeetCode history directly into the
    /// same Keychain-backed caches the real sync paths already read from, so
    /// DEBUG builds never need to touch HealthKit or the LeetCode API just to
    /// populate the Week/Month charts and goal states.
    ///
    /// Runs a one-time 3-month backfill on first launch, then tops up only
    /// whatever days are missing — usually just "today" — on every subsequent
    /// app open (see `seedIfNeeded()`). A day's values, once generated, don't
    /// reshuffle later that same day or on relaunch.
    ///
    /// Gym days additionally get a real `WorkoutSession` (split + per-exercise
    /// sets/reps/skip), written under the same key `GymTracker.workoutSession`
    /// reads from, and the push/pull/legs rotation advances exactly like the
    /// live app does — skipping rotation on rest days, never resetting to
    /// `.push` mid-history.
    ///
    /// To wipe and start over: `DebugDataSeeder.resetAndReseed()` from the
    /// Xcode debugger console (`po DebugDataSeeder.resetAndReseed()`) at a
    /// breakpoint, or from a `print`-triggered call — it deletes everything
    /// under the debug Keychain namespace, resets the split rotation, and
    /// regenerates fresh.
    enum DebugDataSeeder {
        private static let backfillWindowDays = 90

        // MARK: - Public entry points

        /// Call once at app launch, before anything reads step/gym/LeetCode
        /// data. First run ever: generates `backfillWindowDays` days ending
        /// today. Every run after that: fills in only the gap since the last
        /// seeded date.
        static func seedIfNeeded() {
            let today = Calendar.current.startOfDay(for: Date())
            let start: Date = if let lastSeededString = KeychainStore.string(forKey: AppConfig.DefaultsKey.debugSeedLastDateKey),
                                 let lastSeeded = dateFormatter.date(from: lastSeededString)
            {
                Calendar.current.date(byAdding: .day, value: 1, to: lastSeeded) ?? today
            } else {
                Calendar.current.date(byAdding: .day, value: -(backfillWindowDays - 1), to: today) ?? today
            }

            guard start <= today else { return } // already seeded through today

            generate(from: start, through: today)
            KeychainStore.setString(dateFormatter.string(from: today), forKey: AppConfig.DefaultsKey.debugSeedLastDateKey)
        }

        /// Wipes every key in the debug Keychain namespace, resets the
        /// push/pull/legs rotation cursor, and generates a completely fresh
        /// `backfillWindowDays`-day history ending today.
        static func resetAndReseed() {
            KeychainStore.removeAll()
            UserDefaults.standard.removeObject(forKey: AppConfig.DefaultsKey.gymLastCompletedSplit)

            let today = Calendar.current.startOfDay(for: Date())
            let start = Calendar.current.date(byAdding: .day, value: -(backfillWindowDays - 1), to: today) ?? today
            generate(from: start, through: today)
            KeychainStore.setString(dateFormatter.string(from: today), forKey: AppConfig.DefaultsKey.debugSeedLastDateKey)
        }

        // MARK: - Reads used by HealthKitManager in DEBUG

        static func stepsToday() -> Int {
            Int(KeychainStore.double(forKey: stepsKey(for: Date())))
        }

        static func stepsHistory(days: Int, endingOn endDate: Date = Date()) -> [(date: Date, steps: Int)] {
            let calendar = Calendar.current
            var result: [(date: Date, steps: Int)] = []
            for offset in stride(from: days - 1, through: 0, by: -1) {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: endDate) else { continue }
                let steps = Int(KeychainStore.double(forKey: stepsKey(for: day)))
                result.append((date: calendar.startOfDay(for: day), steps: steps))
            }
            return result
        }

        // MARK: - Generation

        private static func generate(from start: Date, through end: Date) {
            let calendar = Calendar.current
            var day = calendar.startOfDay(for: start)
            let lastDay = calendar.startOfDay(for: end)

            // Continue the rotation from wherever the real app (or a prior
            // seeding pass) left it — never restart at .push mid-history.
            var rotationCursor: WorkoutSplit? = UserDefaults.standard
                .string(forKey: AppConfig.DefaultsKey.gymLastCompletedSplit)
                .flatMap(WorkoutSplit.init(rawValue:))

            while day <= lastDay {
                seedSteps(for: day)
                seedGym(for: day, rotationCursor: &rotationCursor)
                seedLeetCode(for: day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }

            if let rotationCursor {
                UserDefaults.standard.set(rotationCursor.rawValue, forKey: AppConfig.DefaultsKey.gymLastCompletedSplit)
            }
        }

        private static func seedSteps(for day: Date) {
            let value = randomDailyValue(target: Double(AppConfig.Steps.dailyTarget))
            // Round to a plausible step count, not a suspiciously exact multiple.
            let steps = (value / 50).rounded() * 50
            KeychainStore.setDouble(steps, forKey: stepsKey(for: day))
        }

        /// Seeds the day's total gym seconds (drives the chart bar), then —
        /// only on days that clear the same minimum the live app itself
        /// requires to count a session at all — generates and persists a real
        /// `WorkoutSession` with the rotated split and a plausible sets/reps
        /// log. Days below that minimum are genuine rest days: no session,
        /// and `rotationCursor` doesn't advance, matching `loadTodaySplit()`'s
        /// real "skip a day, rotation picks up where it left off" behavior.
        private static func seedGym(for day: Date, rotationCursor: inout WorkoutSplit?) {
            let rawSeconds = randomDailyValue(target: AppConfig.Gym.targetDurationSeconds)
            let seconds = (rawSeconds / 30).rounded() * 30 // real sessions don't end on the second
            KeychainStore.setDouble(seconds, forKey: gymSecondsKey(for: day))

            guard seconds >= AppConfig.Gym.minimumRecordedSessionSeconds else {
                return // rest day — no session logged, rotation untouched
            }

            let split = rotationCursor?.next ?? .push
            // How "complete" the session looks, scaled off the same seconds
            // value driving the chart bar — a short day logs fewer sets, a
            // long one logs full (or slightly extra) sets.
            let performance = min(seconds / AppConfig.Gym.targetDurationSeconds, 1.6)

            let exercises: [ExerciseLog] = split.exercises.map { prescribed in
                // Off days occasionally skip one exercise entirely — never on
                // a day that already cleared the target.
                let skipped = performance < 0.7 && Double.random(in: 0 ... 1) < 0.15
                guard !skipped else {
                    return ExerciseLog(name: prescribed.name, reps: 0, setsDone: 0, skipped: true)
                }

                let setsDone = min(
                    max(0, Int((Double(prescribed.sets) * performance).rounded())),
                    prescribed.sets + 1
                )

                // Off days occasionally skip one exercise entirely — never on a day
                // that already cleared the target. A day where nothing got logged
                // (setsDone == 0) is functionally the same thing, so it's folded into
                // the same skipped state rather than persisting a hollow "0×N".
                let explicitSkip = performance < 0.7 && Double.random(in: 0 ... 1) < 0.15
                guard !explicitSkip, setsDone > 0 else {
                    return ExerciseLog(name: prescribed.name, reps: 0, setsDone: 0, skipped: true)
                }

                let reps = max(1, prescribed.reps + Int.random(in: -1 ... 1))
                return ExerciseLog(name: prescribed.name, reps: reps, setsDone: setsDone, skipped: false)
            }

            let session = WorkoutSession(split: split, exercises: exercises)
            if let data = try? JSONEncoder().encode(session), let json = String(data: data, encoding: .utf8) {
                KeychainStore.setString(json, forKey: gymSessionKey(for: day))
            }

            rotationCursor = split
        }

        private static func seedLeetCode(for day: Date) {
            let total = Int(randomDailyValue(target: Double(AppConfig.LeetCode.dailyTargetProblems)).rounded())

            // Split into a realistic easy/medium/hard mix — most days lean easy.
            var easy = 0, medium = 0, hard = 0
            for _ in 0 ..< total {
                switch Double.random(in: 0 ... 1) {
                case ..<0.5: easy += 1
                case ..<0.85: medium += 1
                default: hard += 1
                }
            }

            let dateKey = dateFormatter.string(from: day)
            let prefix = AppConfig.DefaultsKey.leetcodeDailyCountPrefix
            KeychainStore.setInt(total, forKey: prefix + dateKey)
            KeychainStore.setInt(easy, forKey: prefix + AppConfig.DefaultsKey.leetcodeEasySuffix + dateKey)
            KeychainStore.setInt(medium, forKey: prefix + AppConfig.DefaultsKey.leetcodeMediumSuffix + dateKey)
            KeychainStore.setInt(hard, forKey: prefix + AppConfig.DefaultsKey.leetcodeHardSuffix + dateKey)
        }

        /// Realistic-ish daily performance: ~8% near-total miss (rest/lazy
        /// day), ~55% meets or exceeds the goal, the rest lands somewhere
        /// partial — nobody hits the exact target every single day.
        private static func randomDailyValue(target: Double, meetProbability: Double = 0.55) -> Double {
            if Double.random(in: 0 ... 1) < 0.08 {
                return Double.random(in: 0 ... (target * 0.1))
            }
            if Double.random(in: 0 ... 1) < meetProbability {
                return target * Double.random(in: 1.0 ... 1.6)
            }
            return target * Double.random(in: 0.15 ... 0.95)
        }

        // MARK: - Keys / formatting

        private static func stepsKey(for day: Date) -> String {
            AppConfig.DefaultsKey.debugStepsPrefix + dateFormatter.string(from: day)
        }

        private static func gymSecondsKey(for day: Date) -> String {
            AppConfig.DefaultsKey.gymSecondsPrefix + dateFormatter.string(from: day)
        }

        private static func gymSessionKey(for day: Date) -> String {
            AppConfig.DefaultsKey.gymWorkoutSessionPrefix + dateFormatter.string(from: day)
        }

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }()
    }
#endif
