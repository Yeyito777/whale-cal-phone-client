#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -swift-version 6 WhaleCal/Core/CalendarModels.swift WhaleCal/Core/SSHConnectionConfiguration.swift Tests/ModelTests.swift -o .build/model-tests
.build/model-tests
