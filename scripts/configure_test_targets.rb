#!/usr/bin/env ruby

require "xcodeproj"

root = File.expand_path("..", __dir__)
project_path = File.join(root, "Reasi.xcodeproj")
project = Xcodeproj::Project.open(project_path)
app_target = project.targets.find { |target| target.name == "Reasi" }
abort "Reasi app target was not found" unless app_target

def ensure_group(project, name)
  group = project.main_group.find_subpath(name, true)
  group.path = name
  group.source_tree = "<group>"
  group
end

def ensure_file(group, path)
  group.files.find { |file| file.path == path } || group.new_reference(path)
end

def configure_test_target(target, bundle_id:, test_host: false)
  target.build_configurations.each do |configuration|
    settings = configuration.build_settings
    settings["CODE_SIGN_STYLE"] = "Automatic"
    settings["GENERATE_INFOPLIST_FILE"] = "YES"
    settings["IPHONEOS_DEPLOYMENT_TARGET"] = "26.0"
    settings["PRODUCT_BUNDLE_IDENTIFIER"] = bundle_id
    settings["PRODUCT_NAME"] = "$(TARGET_NAME)"
    settings["SWIFT_STRICT_CONCURRENCY"] = "complete"
    settings["SWIFT_VERSION"] = "6.0"
    settings["TARGETED_DEVICE_FAMILY"] = "1"

    next unless test_host

    settings["BUNDLE_LOADER"] = "$(TEST_HOST)"
    settings["TEST_HOST"] = "$(BUILT_PRODUCTS_DIR)/Reasi.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Reasi"
  end
end

unit_target = project.targets.find { |target| target.name == "ReasiTests" }
unit_target ||= project.new_target(:unit_test_bundle, "ReasiTests", :ios, "26.0")
unit_target.add_dependency(app_target) unless unit_target.dependencies.any? { |dependency| dependency.target == app_target }
configure_test_target(unit_target, bundle_id: "ai.reasi.ios.tests", test_host: true)

unit_group = ensure_group(project, "ReasiTests")
unit_file = ensure_file(unit_group, "ReasiCoreTests.swift")
unit_target.add_file_references([unit_file]) unless unit_target.source_build_phase.files_references.include?(unit_file)

ui_target = project.targets.find { |target| target.name == "ReasiUITests" }
ui_target ||= project.new_target(:ui_test_bundle, "ReasiUITests", :ios, "26.0")
ui_target.add_dependency(app_target) unless ui_target.dependencies.any? { |dependency| dependency.target == app_target }
configure_test_target(ui_target, bundle_id: "ai.reasi.ios.uitests")
ui_target.build_configurations.each do |configuration|
  configuration.build_settings["TEST_TARGET_NAME"] = "Reasi"
end

ui_group = ensure_group(project, "ReasiUITests")
ui_file = ensure_file(ui_group, "ReasiOnboardingUITests.swift")
ui_target.add_file_references([ui_file]) unless ui_target.source_build_phase.files_references.include?(ui_file)

# xcodeproj adds an SDK-pinned Foundation reference when creating a test target.
# Swift imports Foundation through SDK auto-linking, so remove the stale path and
# let the selected Xcode toolchain supply the iOS 26 framework.
[unit_target, ui_target].each do |target|
  target.frameworks_build_phase.files.each do |build_file|
    build_file.remove_from_project if build_file.file_ref&.path&.end_with?("Foundation.framework")
  end
end
project.files
  .select { |file| file.path&.end_with?("Foundation.framework") }
  .each(&:remove_from_project)

project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app_target)
scheme.add_test_target(unit_target)
scheme.add_test_target(ui_target)
scheme.set_launch_target(app_target)
scheme.save_as(project_path, "Reasi", true)
