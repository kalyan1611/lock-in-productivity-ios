import SwiftUI

struct ActivityCard: View {
    @Binding var selectedTab: GoalTab
    @Binding var selectedPeriod: StatsPeriod

    @ObservedObject var healthKit: HealthKitManager
    @ObservedObject var gymTracker: GymTracker
    @ObservedObject var leetCode: LeetCodeManager

    let waiveOffStatus: NetworkManager.WaiveOffStatus?
    let onTapWaiveOff: (NetworkManager.WaiveOffType) -> Void

    /// +1 when the most recent tab change moved rightward through
    /// GoalTab.allCases (Steps → Gym → LeetCode), -1 when it moved
    /// leftward. Drives which edge `tabTransition` slides in/out from.
    /// Set synchronously alongside `selectedTab` itself (see
    /// `GoalTabSwitcher.onSelect` below) so both land in the same
    /// transaction — if this lagged a render behind, the very tab switch
    /// it's meant to describe would animate with the previous direction.
    @State private var tabDirection: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            GoalTabSwitcher(selection: $selectedTab) { old, new in
                let oldIndex = GoalTab.allCases.firstIndex(of: old) ?? 0
                let newIndex = GoalTab.allCases.firstIndex(of: new) ?? 0
                tabDirection = newIndex >= oldIndex ? 1 : -1
            }

            // .topLeading matters here — without an explicit alignment this
            // frame defaults to centering non-expanding content (that's why
            // today's stat was rendering centered before), pushing it away
            // from the card's top-left and leaving dead space below.
            //
            // `.id(selectedTab)` gives each tab's content its own view
            // identity, which is what makes `.transition` fire at all —
            // without it this is just one persistent view whose internals
            // happen to change, and SwiftUI has nothing to insert/remove.
            // `.clipped()` keeps the sliding content from poking outside
            // the card's rounded corners mid-animation.
            tabContent
                .id(selectedTab)
                .transition(tabTransition)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Palette.surfaceStroke, lineWidth: 1)
        )
    }

    // MARK: - Tab content dispatch

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .steps:
            stepsContent
        case .gym:
            gymContent
        case .leetcode:
            leetCodeContent
        }
    }

    /// New content enters from the direction of travel and old content
    /// exits the opposite way — a standard slide-page effect. Both sides
    /// fade slightly too, which hides the fact that the three tabs'
    /// content isn't the same height (a pure slide with mismatched
    /// heights can look like it's "snagging" on the shorter view).
    private var tabTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: tabDirection >= 0 ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: tabDirection >= 0 ? .leading : .trailing).combined(with: .opacity)
        )
    }

    // MARK: - Header (title + ticket badge tied to selected tab)

    private var isCompletedForTab: Bool {
        switch selectedTab {
        case .steps: healthKit.areTodaysStepsCompleted
        case .gym: gymTracker.isGymSessionCompleted
        case .leetcode: leetCode.isGoalMet
        }
    }

    private var waivedForTab: Bool {
        switch selectedTab {
        case .steps: waiveOffStatus?.stepsWaivedToday ?? false
        case .gym: waiveOffStatus?.gymWaivedToday ?? false
        case .leetcode: waiveOffStatus?.leetcodeWaivedToday ?? false
        }
    }

    private var waiveRemainingForTab: Int? {
        switch selectedTab {
        case .steps: waiveOffStatus?.stepsRemaining
        case .gym: waiveOffStatus?.gymRemaining
        case .leetcode: waiveOffStatus?.leetcodeRemaining
        }
    }

    private var header: some View {
        HStack {
            Text("ACTIVITY")
                .font(Typography.eyebrow)
                .tracking(1.5)
                .foregroundStyle(Palette.textSecondary)

            Spacer()

            if !isCompletedForTab,
               !waivedForTab,
               TimeUtils.isFreeTime(),
               let remaining = waiveRemainingForTab
            {
                TicketBadge(remaining: remaining) {
                    onTapWaiveOff(selectedTab.waiveOffType)
                }
            }
        }
    }

    // MARK: - Steps

    // stepsUntilNextChunk mirrors the firmware's STEPS_PER_CREDIT_CHUNK
    // (1000 steps = +10m, capped at the daily target) — kept in sync
    // manually with dns_filter.ino's tieredMinutesFromProgress(). Computed
    // locally from HealthKit data the app already has, rather than
    // round-tripping through the ESP32, so it's live rather than only as
    // fresh as the last /sync.

    private var stepsUntilNextChunk: Int? {
        let chunk = 1000
        let steps = healthKit.todaySteps
        let target = healthKit.targetSteps
        guard steps < target else { return nil }
        let nextThreshold = min(((steps / chunk) + 1) * chunk, target)
        let remaining = nextThreshold - steps
        return remaining > 0 ? remaining : nil
    }

    private var stepsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            todayStat(
                value: "\(healthKit.todaySteps)",
                unit: "of \(healthKit.targetSteps) steps",
                progress: healthKit.targetSteps > 0
                    ? Double(healthKit.todaySteps) / Double(healthKit.targetSteps) : 0,
                isCompleted: healthKit.areTodaysStepsCompleted,
                waived: waiveOffStatus?.stepsWaivedToday ?? false,
                creditNote: stepsUntilNextChunk.map { "\($0) to next +10m" }
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().overlay(Palette.surfaceStroke)

            PeriodSwitcher(selection: $selectedPeriod)

            PagedActivityChart(
                totalPages: totalPages,
                period: selectedPeriod,
                target: Double(healthKit.targetSteps),
                valueLabel: { "\(Int($0))" },
                showTargetLine: false,
                rangeLabel: { periodRangeLabel(forPage: $0) },
                subtitle: { pageSubtitle(forPage: $0) },
                fetchEntries: { await stepsEntries(forPage: $0) },
                detailFor: { entry in
                    SelectedBarDetail(
                        dateText: fullDateLabel(entry.date),
                        totalText: "\(Int(entry.total))",
                        unitText: "steps",
                        totalColor: entry.total >= Double(healthKit.targetSteps) ? Palette.open : Palette.textPrimary,
                        breakdown: []
                    )
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func stepsEntries(forPage page: Int) async -> [ActivityBarChart.Entry] {
        let history = await (try? healthKit.fetchStepsHistory(days: daysPerPeriod, endingOn: referenceDate(forPage: page))) ?? []
        return history.map { day in
            let met = healthKit.targetSteps > 0 ? Double(day.steps) >= Double(healthKit.targetSteps) : false
            return ActivityBarChart.Entry(
                date: day.date,
                segments: [
                    ActivityBarChart.Segment(
                        value: Double(day.steps),
                        color: met ? Palette.open : Palette.started
                    ),
                ]
            )
        }
    }

    // MARK: - Gym

    private var gymContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            todayStat(
                value: "\(Int(gymTracker.totalSecondsToday) / 60) min",
                unit: "of \(gymTracker.targetGymDurationMinutes) min target",
                progress: gymTracker.targetGymDurationSeconds > 0
                    ? gymTracker.totalSecondsToday / gymTracker.targetGymDurationSeconds : 0,
                isCompleted: gymTracker.isGymSessionCompleted,
                waived: waiveOffStatus?.gymWaivedToday ?? false,
                creditNote: gymTracker.isGymSessionCompleted ? nil : "Full session: +\(gymTracker.targetGymDurationMinutes)m"
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            gymActionButton

            Divider().overlay(Palette.surfaceStroke)

            PeriodSwitcher(selection: $selectedPeriod)

            PagedActivityChart(
                totalPages: totalPages,
                period: selectedPeriod,
                target: Double(gymTracker.targetGymDurationMinutes),
                valueLabel: { "\(Int($0))m" },
                showTargetLine: false,
                rangeLabel: { periodRangeLabel(forPage: $0) },
                subtitle: { pageSubtitle(forPage: $0) },
                fetchEntries: { await gymEntries(forPage: $0) },
                detailFor: { entry in
                    SelectedBarDetail(
                        dateText: fullDateLabel(entry.date),
                        totalText: "\(Int(entry.total))",
                        unitText: "min",
                        totalColor: entry.total >= Double(gymTracker.targetGymDurationMinutes) ? Palette.open : Palette.textPrimary,
                        breakdown: []
                    )
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func gymEntries(forPage page: Int) async -> [ActivityBarChart.Entry] {
        let history = gymTracker.secondsHistory(days: daysPerPeriod, endingOn: referenceDate(forPage: page))
        return history.map { day in
            let minutes = day.seconds / 60
            let met = minutes >= Double(gymTracker.targetGymDurationMinutes)
            return ActivityBarChart.Entry(
                date: day.date,
                segments: [
                    ActivityBarChart.Segment(
                        value: minutes,
                        color: met ? Palette.open : Palette.started
                    ),
                ]
            )
        }
    }

    // gymGuidanceLabel restores the pre-revamp "Inside gym zone" / distance
    // / "Location unknown" row, and workoutDurationText restores the
    // post-checkout "Workout duration: N mins" line — both were dropped
    // when this moved from the standalone GymCard into ActivityCard.

    @ViewBuilder
    private var gymActionButton: some View {
        if gymTracker.isCheckedIn, let checkInDate = gymTracker.checkInDate {
            VStack(spacing: 10) {
                GymCountdownButton(gymTracker: gymTracker, checkInDate: checkInDate)
                gymGuidanceLabel
            }
        } else if gymTracker.hasCheckedOutToday {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Session complete")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.open)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Capsule().fill(Palette.open.opacity(0.12)))

                Text(workoutDurationText)
                    .font(.caption2)
                    .foregroundStyle(Palette.textSecondary)
            }
        } else {
            VStack(spacing: 10) {
                Button {
                    gymTracker.checkIn()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.strengthtraining.traditional")
                        Text("Check In")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                }
                .buttonStyle(.plain)
                .foregroundStyle(gymTracker.isInsideGeofence ? Palette.background : Palette.textSecondary)
                .background(Capsule().fill(gymTracker.isInsideGeofence ? Palette.open : Palette.surfaceStroke))
                .disabled(!gymTracker.isInsideGeofence)

                gymGuidanceLabel
            }
        }
    }

    private var gymGuidanceLabel: some View {
        Group {
            if gymTracker.isInsideGeofence {
                gymGuidanceRow(icon: "location.fill", text: "Inside gym zone", tint: Palette.open)
            } else if gymTracker.distanceToGym != nil {
                gymGuidanceRow(icon: "location", text: formattedDistance, tint: Palette.textSecondary)
            } else {
                gymGuidanceRow(icon: "location.slash", text: "Location unknown", tint: Palette.textSecondary)
            }
        }
        .font(.caption2)
    }

    private func gymGuidanceRow(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .foregroundStyle(tint)
    }

    private var formattedDistance: String {
        guard let distance = gymTracker.distanceToGym else { return "" }
        return distance >= 1000
            ? String(format: "%.1f km away", distance / 1000)
            : String(format: "%.0f m away", distance)
    }

    private var workoutDurationText: String {
        guard let inTime = gymTracker.lastCheckInDate, let outTime = gymTracker.lastCheckOutDate else {
            return "Workout logged for today"
        }
        let minutes = Int(outTime.timeIntervalSince(inTime) / 60)
        return "Workout duration: \(minutes) mins"
    }

    // MARK: - LeetCode

    private var leetCodeContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            todayStat(
                value: "\(leetCode.totalTodayCount)",
                unit: "of \(leetCode.targetProblems) problems",
                progress: leetCode.progress,
                isCompleted: leetCode.isGoalMet,
                waived: waiveOffStatus?.leetcodeWaivedToday ?? false
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            difficultyBreakdown

            Divider().overlay(Palette.surfaceStroke)

            PeriodSwitcher(selection: $selectedPeriod)

            PagedActivityChart(
                totalPages: totalPages,
                period: selectedPeriod,
                target: Double(leetCode.targetProblems),
                valueLabel: { "\(Int($0))" },
                rangeLabel: { periodRangeLabel(forPage: $0) },
                subtitle: { pageSubtitle(forPage: $0) },
                fetchEntries: { await leetCodeEntries(forPage: $0) },
                detailFor: { entry in
                    SelectedBarDetail(
                        dateText: fullDateLabel(entry.date),
                        totalText: "\(Int(entry.total))",
                        unitText: "solved",
                        totalColor: entry.total >= Double(leetCode.targetProblems) ? Palette.open : Palette.textPrimary,
                        breakdown: [
                            (label: "EASY", value: "\(Int(entry.segments[0].value))", color: Palette.open),
                            (label: "MEDIUM", value: "\(Int(entry.segments[1].value))", color: Palette.waived),
                            (label: "HARD", value: "\(Int(entry.segments[2].value))", color: Palette.locked),
                        ]
                    )
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !leetCode.hasMultiDayHistory() {
                Text("History builds day by day from today — full backdated history needs LeetCode's calendar API.")
                    .font(.caption2)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private func leetCodeEntries(forPage page: Int) async -> [ActivityBarChart.Entry] {
        let breakdown = leetCode.breakdownHistory(days: daysPerPeriod, endingOn: referenceDate(forPage: page))
        return breakdown.map { day in
            ActivityBarChart.Entry(date: day.date, segments: [
                ActivityBarChart.Segment(value: Double(day.easy), color: Palette.open),
                ActivityBarChart.Segment(value: Double(day.medium), color: Palette.waived),
                ActivityBarChart.Segment(value: Double(day.hard), color: Palette.locked),
            ])
        }
    }

    private var difficultyBreakdown: some View {
        HStack(spacing: 0) {
            difficultyColumn(label: "EASY", count: leetCode.easyTodayCount, creditLabel: "+5m", color: Palette.open)
            Divider().overlay(Palette.surfaceStroke).frame(height: 20)
            difficultyColumn(label: "MEDIUM", count: leetCode.mediumTodayCount, creditLabel: "+10m", color: Palette.waived)
            Divider().overlay(Palette.surfaceStroke).frame(height: 20)
            difficultyColumn(label: "HARD", count: leetCode.hardTodayCount, creditLabel: "+15m", color: Palette.locked)
        }
    }

    private func difficultyColumn(label: String, count: Int, creditLabel: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Palette.textPrimary)
            Text(creditLabel)
                .font(.system(size: 9))
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Shared "today" stat block

    // Horizontal progress bar replaces the old ring+icon combo — the icon
    // duplicated what GoalTabSwitcher already shows, so it's dropped
    // entirely rather than relocated. creditNote restores the per-tab
    // "what do I earn" line that existed pre-revamp (StepsCard's chunked
    // "+10m per 1000 steps", GymCard's flat "Full session: +45m").

    /// "Wed, Feb 12" — used by each tab's SelectedBarDetail row.
    private func fullDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    private func todayStat(
        value: String,
        unit: String,
        progress: Double,
        isCompleted: Bool,
        waived: Bool,
        creditNote: String? = nil
    ) -> some View {
        let color = GoalColor.forProgress(progress, isCompleted: isCompleted, waived: waived)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(Typography.display(28))
                    .foregroundStyle(Palette.textPrimary)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Palette.surfaceStroke)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * min(max(progress, 0), 1))
                }
            }
            .frame(height: 8)

            if let creditNote {
                Text(creditNote)
                    .font(.caption2)
                    .foregroundStyle(Palette.neutral)
            }
        }
    }

    // MARK: - Paging helpers

    // How many calendar days one page covers, and how many pages are
    // offered total. Pages are capped (8 weeks / 6 months) rather than
    // unbounded — infinite paging would need a windowed/recycling
    // TabView, which is overkill here; bump these if it ever feels short.

    private var daysPerPeriod: Int {
        selectedPeriod == .week ? 7 : 30
    }

    private var totalPages: Int {
        selectedPeriod == .week ? 8 : 6
    }

    /// How many periods back page `page` is, given `page 0` is the oldest
    /// and `totalPages - 1` is the current (today-ending) period. This
    /// ordering — old on the left, current on the right — is what makes
    /// left-to-right swiping feel like paging backward in time.
    private func weeksAgo(forPage page: Int) -> Int {
        max(totalPages - 1 - page, 0)
    }

    private func referenceDate(forPage page: Int) -> Date {
        let ago = weeksAgo(forPage: page)
        return Calendar.current.date(byAdding: .day, value: -(daysPerPeriod * ago), to: Date()) ?? Date()
    }

    private func periodRangeLabel(forPage page: Int) -> String {
        let calendar = Calendar.current
        let end = referenceDate(forPage: page)
        let start = calendar.date(byAdding: .day, value: -(daysPerPeriod - 1), to: end) ?? end
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let startText = formatter.string(from: start)
        let endText = weeksAgo(forPage: page) == 0 ? "Today" : formatter.string(from: end)
        return "\(startText) – \(endText)"
    }

    private func pageSubtitle(forPage page: Int) -> String {
        let unit = selectedPeriod == .week ? "week" : "month"
        let ago = weeksAgo(forPage: page)
        if ago == 0 {
            return "This \(unit)"
        }
        return "\(ago) \(unit)\(ago > 1 ? "s" : "") ago"
    }
}

// MARK: - Gym Countdown Button

/// Pulled out of ActivityCard's gymActionButton if/else chain on purpose:
/// TimelineView is a heavily generic type, and mixing it directly into a
/// multi-branch @ViewBuilder if/else caused a "Generic parameter 'Content'
/// could not be inferred" error. Isolating it in its own view, and further
/// isolating the button-building work into a plain method with a small
/// number of let bindings, keeps each piece simple enough for the type
/// checker to resolve.
private struct GymCountdownButton: View {
    @ObservedObject var gymTracker: GymTracker
    let checkInDate: Date

    var body: some View {
        TimelineView(.periodic(from: checkInDate, by: 1)) { context in
            countdownButton(at: context.date)
        }
    }

    private func countdownButton(at now: Date) -> some View {
        let elapsed = now.timeIntervalSince(checkInDate)
        let canCheckOut = elapsed >= gymTracker.targetGymDurationSeconds
        let readyToCheckOut = canCheckOut && gymTracker.isInsideGeofence
        let remaining = max(gymTracker.targetGymDurationSeconds - elapsed, 0)
        let label = canCheckOut ? "Check Out" : timeString(from: remaining)
        let icon = canCheckOut ? "figure.walk.departure" : "timer"

        return Button {
            gymTracker.checkOut()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(label).monospacedDigit()
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
        }
        .buttonStyle(.plain)
        .foregroundStyle(readyToCheckOut ? Palette.background : Palette.textSecondary)
        .background(Capsule().fill(readyToCheckOut ? Palette.open : Palette.surfaceStroke))
        .disabled(!readyToCheckOut)
    }

    private func timeString(from seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Paged Activity Chart

/// Wraps ActivityBarChart in a horizontally-swipeable TabView so the user
/// can page back through past weeks/months, not just see the current one.
/// Pages are ordered oldest → newest, left → right (page 0 is the oldest,
/// the last page always ends on today), which is what makes swiping left
/// feel like paging backward in time and keeps the transition into the
/// current period smooth rather than jumping.
///
/// Owns its own page index + per-page entry cache + tapped-bar state, so
/// switching weeks doesn't need to round-trip through ActivityCard at all.
/// Re-created fresh whenever the parent tab changes (steps/gym/leetcode
/// each get their own instance), and resets itself internally whenever
/// `period` (week/month) changes.
private struct PagedActivityChart: View {
    let totalPages: Int
    let period: StatsPeriod
    let target: Double
    let valueLabel: (Double) -> String
    var showTargetLine: Bool = true
    /// "Aug 31 – Today" / "Aug 24 – Aug 30" etc., for the page currently on screen.
    let rangeLabel: (Int) -> String
    /// "This week" / "2 weeks ago" etc.
    let subtitle: (Int) -> String
    let fetchEntries: (Int) async -> [ActivityBarChart.Entry]
    let detailFor: (ActivityBarChart.Entry) -> SelectedBarDetail

    @State private var pageIndex: Int
    @State private var selectedBarIndex: Int?
    @State private var cache: [Int: [ActivityBarChart.Entry]] = [:]

    init(
        totalPages: Int,
        period: StatsPeriod,
        target: Double,
        valueLabel: @escaping (Double) -> String,
        showTargetLine: Bool = true,
        rangeLabel: @escaping (Int) -> String,
        subtitle: @escaping (Int) -> String,
        fetchEntries: @escaping (Int) async -> [ActivityBarChart.Entry],
        detailFor: @escaping (ActivityBarChart.Entry) -> SelectedBarDetail
    ) {
        self.totalPages = totalPages
        self.period = period
        self.target = target
        self.valueLabel = valueLabel
        self.showTargetLine = showTargetLine
        self.rangeLabel = rangeLabel
        self.subtitle = subtitle
        self.fetchEntries = fetchEntries
        self.detailFor = detailFor
        // Open on the last page (today's period), not the oldest one.
        _pageIndex = State(initialValue: max(totalPages - 1, 0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if period == .month,
               let entries = cache[pageIndex],
               let index = selectedBarIndex,
               entries.indices.contains(index)
            {
                detailFor(entries[index])
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            TabView(selection: $pageIndex) {
                ForEach(0 ..< totalPages, id: \.self) { page in
                    ActivityBarChart(
                        entries: cache[page] ?? [],
                        target: target,
                        period: period,
                        selectedIndex: barSelection(for: page),
                        valueLabel: valueLabel,
                        showTargetLine: showTargetLine
                    )
                    .tag(page)
                    .task(id: page) {
                        guard cache[page] == nil else { return }
                        cache[page] = await fetchEntries(page)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeInOut(duration: 0.2), value: selectedBarIndex)
        .onAppear {
            // .page TabView doesn't reliably honor the State's initial
            // value on first mount — it tends to just land on tag 0
            // regardless. Forcing it here guarantees we always open on
            // "today" (the last page) rather than the oldest one.
            pageIndex = max(totalPages - 1, 0)
        }
        .onChange(of: period) { _, _ in
            cache = [:]
            pageIndex = max(totalPages - 1, 0)
            selectedBarIndex = nil
        }
        .onChange(of: pageIndex) { _, _ in
            selectedBarIndex = nil
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rangeLabel(pageIndex))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(Palette.textPrimary)
                Text(subtitle(pageIndex))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            if totalPages > 1 {
                Text("SWIPE FOR MORE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    /// ActivityBarChart wants a plain Binding<Int?>, but selection state
    /// really belongs to "whichever page is on screen" — this routes reads
    /// and writes through that single piece of state, gated to the page
    /// asking for it, so swiping away from a page silently drops its
    /// selection instead of leaking into whatever page you land on next.
    private func barSelection(for page: Int) -> Binding<Int?> {
        Binding(
            get: { pageIndex == page ? selectedBarIndex : nil },
            set: { newValue in
                guard pageIndex == page else { return }
                selectedBarIndex = newValue
            }
        )
    }
}

#Preview("iPhone") {
    ContentView()
}

// MARK: - Selected Bar Detail

/// Readable stand-in for the per-bar label month view can't fit. Rendered
/// between the Week/Month switcher and the chart itself whenever a month
/// bar is tapped, so there's a full-width row of room instead of squeezing
/// text above a ~7pt-wide bar.
struct SelectedBarDetail: View {
    let dateText: String
    let totalText: String
    let unitText: String
    let totalColor: Color
    /// Per-segment rows (e.g. Easy/Medium/Hard). Empty for single-value
    /// charts (Steps, Gym), which just show the date + total.
    let breakdown: [(label: String, value: String, color: Color)]

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateText)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(Palette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(totalText)
                        .font(Typography.display(22))
                        .foregroundStyle(totalColor)
                        .contentTransition(.numericText())
                    Text(unitText)
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }

            Spacer(minLength: 12)

            if !breakdown.isEmpty {
                HStack(spacing: 14) {
                    ForEach(Array(breakdown.enumerated()), id: \.offset) { _, item in
                        VStack(spacing: 3) {
                            HStack(spacing: 4) {
                                Circle().fill(item.color).frame(width: 6, height: 6)
                                Text(item.label)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Palette.textSecondary)
                            }
                            Text(item.value)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Palette.textPrimary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.surfaceStroke, lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
