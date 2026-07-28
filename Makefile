DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

SCHEME := MealNotes
SIMULATOR ?= iPhone 16
DESTINATION := platform=iOS Simulator,name=$(SIMULATOR)
PACKAGE := Packages/MealNotesCore

.PHONY: help simulators build test test-core test-app clean

help:
	@echo "make build      — build the app for the $(SIMULATOR) simulator"
	@echo "make test       — run every test (core package, then app and UI tests)"
	@echo "make test-core  — run the MealNotesCore package tests only (fast)"
	@echo "make test-app   — run the app unit tests and the UI test on the simulator"
	@echo "make simulators — list the simulators available on this machine"
	@echo ""
	@echo "Override the simulator with:  make test SIMULATOR='iPhone 17'"

simulators:
	@xcrun simctl list devices available | grep -E "^--|iPhone"

build:
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' -configuration Debug build

# Two commands because the core package's tests live in a Swift package and the
# app's tests live in the Xcode project. `xcodebuild` is the source of truth for
# anything that has to run on iOS; `swift test` is the fast inner loop for the
# pure logic, which is where most of the safety-critical behaviour lives.
test: test-core test-app

test-core:
	cd $(PACKAGE) && swift test

test-app:
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' -configuration Debug test

clean:
	xcodebuild -scheme $(SCHEME) clean
	rm -rf $(PACKAGE)/.build
