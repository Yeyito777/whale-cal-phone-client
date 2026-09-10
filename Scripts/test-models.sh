#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -swift-version 6 WhaleCal/Core/CalendarModels.swift WhaleCal/Core/DeadlineSchedule.swift WhaleCal/Core/DayTimelineLayout.swift WhaleCal/Core/SSHConnectionConfiguration.swift WhaleCal/Core/CalendarDrawerInteraction.swift Tests/ModelTests.swift -o .build/model-tests
.build/model-tests
swiftc -swift-version 6 WhaleCal/Core/CalendarModels.swift WhaleCal/Core/DeadlineSchedule.swift Tests/RecurrenceParity.swift -o .build/recurrence-parity
