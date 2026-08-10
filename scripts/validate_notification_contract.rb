#!/usr/bin/env ruby

require "yaml"
require "json"

path = File.expand_path("../docs/notification-backend.openapi.yaml", __dir__)
spec = YAML.load_file(path)
payload_schema_path = File.expand_path("../docs/notification-payload.schema.json", __dir__)
payload_schema = JSON.parse(File.read(payload_schema_path))
payload_example_path = File.expand_path("../docs/notification-payload.example.json", __dir__)
payload_example = JSON.parse(File.read(payload_example_path))

checks = {
  "OpenAPI version" => spec["openapi"] == "3.0.3",
  "health endpoint" => spec.dig("paths", "/healthz", "get"),
  "device endpoint" => spec.dig("paths", "/v1/devices/{deviceId}", "put"),
  "preferences endpoint" => spec.dig("paths", "/v1/devices/{deviceId}/preferences", "patch"),
  "device registration schema" => spec.dig("components", "schemas", "DeviceRegistration"),
  "payload schema" => payload_schema["required"] == ["aps", "epidemicIdentifier"],
  "payload example" => payload_example.dig("aps", "alert", "title").is_a?(String) &&
    payload_example.dig("aps", "alert", "body").is_a?(String) &&
    payload_example["epidemicIdentifier"].match?(/\\A.+\\|[0-9]+(?:\\.[0-9]+)?\\z/),
}

failed = checks.filter_map { |name, valid| name unless valid }
abort "Invalid notification API contract: #{failed.join(", ")}" unless failed.empty?

puts "OpenAPI contract is valid"
