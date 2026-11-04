#!/usr/bin/env ruby
# One-time, scoped compliance update for the processed CipherVault v1.0 (9).
# The reviewed code uses Apple CryptoKit AES.GCM + Apple CommonCrypto,
# without implementing proprietary algorithms or third-party encryption.
# This script is not a general-purpose Apple-account updater.
require "json"
require "jwt"
require "openssl"
require "net/http"
require "uri"
require "base64"

BUNDLE_ID = "com.jdarkyeka6.calculator"
APP_ID = "6829378196"
BUILD_NUMBER = "9"

def secret(name)
  value = ENV.fetch(name, "").strip
  abort("Missing #{name}") if value.empty?
  value
end

raw = secret("ASC_PRIVATE_KEY")
pem = raw.include?("BEGIN PRIVATE KEY") ? raw.gsub("\\n", "\n") : Base64.strict_decode64(raw.gsub(/\s/, ""))
now = Time.now.to_i
token = JWT.encode(
  {iss: secret("ASC_ISSUER_ID"), iat: now - 20, exp: now + 900, aud: "appstoreconnect-v1"},
  OpenSSL::PKey.read(pem), "ES256", {kid: secret("ASC_KEY_ID"), typ: "JWT"}
)

def request_apple(method, path, token, payload = nil)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  abort("Unexpected Apple API endpoint") unless uri.scheme == "https" && uri.host == "api.appstoreconnect.apple.com"
  klass = {"GET" => Net::HTTP::Get, "PATCH" => Net::HTTP::Patch, "POST" => Net::HTTP::Post}.fetch(method)
  req = klass.new(uri)
  req["Authorization"] = "Bearer #{token}"
  req["Accept"] = "application/json"
  if payload
    req["Content-Type"] = "application/json"
    req.body = JSON.generate(payload)
  end
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) do |http|
    http.request(req)
  end
  unless %w[200 201 204].include?(response.code)
    abort("Apple API #{method} #{path.split('?').first} HTTP #{response.code}: #{response.body.to_s[0, 700]}")
  end
  response.body.to_s.empty? ? {} : JSON.parse(response.body)
end

apps = request_apple("GET", "/v1/apps?filter%5BbundleId%5D=#{BUNDLE_ID}&limit=10", token).fetch("data", [])
app = apps.find { |a| a["id"] == APP_ID && a.dig("attributes", "bundleId") == BUNDLE_ID }
abort("Wrong app: refused to update Apple account") unless app
puts "CONFIRMED_APP id=#{APP_ID} bundle=#{BUNDLE_ID}"

builds = request_apple("GET", "/v1/apps/#{APP_ID}/builds?limit=100", token).fetch("data", [])
target = builds.find { |b| b.dig("attributes", "version") == BUILD_NUMBER }
abort("BUILD_9_NOT_FOUND; no changes made") unless target
build_id = target.fetch("id")
attrs = target.fetch("attributes")
abort("Build is not processed; no changes made") unless attrs.fetch("processingState") == "VALID"
abort("Build explicitly classified as non-exempt; refuse to overwrite") if attrs["usesNonExemptEncryption"] == true

unless attrs["usesNonExemptEncryption"] == false
  request_apple("PATCH", "/v1/builds/#{build_id}", token, {
    data: {type: "builds", id: build_id, attributes: {usesNonExemptEncryption: false}}
  })
  puts "COMPLIANCE_UPDATED build=#{BUILD_NUMBER} usesNonExemptEncryption=false"
end

verify = request_apple("GET", "/v1/builds/#{build_id}", token).fetch("data")
abort("FAILED_VERIFICATION: build 9 not classified as exempt") unless verify.dig("attributes", "usesNonExemptEncryption") == false
puts "COMPLIANCE_VERIFIED build=#{BUILD_NUMBER} usesNonExemptEncryption=false"

detail = request_apple("GET", "/v1/builds/#{build_id}/buildBetaDetail", token)
beta_attrs = detail.fetch("data", {}).fetch("attributes", {})
puts "BETA_BEFORE_LINK build=#{BUILD_NUMBER} internal=#{beta_attrs['internalBuildState']} external=#{beta_attrs['externalBuildState']}"
abort("Build 9 remains unavailable; review beta state before adding testers") if beta_attrs["internalBuildState"] == "MISSING_EXPORT_COMPLIANCE"

groups = request_apple("GET", "/v1/apps/#{APP_ID}/betaGroups?limit=30", token).fetch("data", [])
internal = groups.find do |g|
  a = g.fetch("attributes", {})
  a["name"] == "Testers" && a["isInternalGroup"] == true
end
abort("Known internal Testers group not found; no group changes made") unless internal
group_id = internal.fetch("id")
group_builds = request_apple("GET", "/v1/betaGroups/#{group_id}/relationships/builds?limit=200", token).fetch("data", [])
unless group_builds.any? { |b| b["id"] == build_id }
  request_apple("POST", "/v1/betaGroups/#{group_id}/relationships/builds", token,
                {data: [{type: "builds", id: build_id}]})
  puts "BETA_GROUP_LINKED build=#{BUILD_NUMBER} group=Testers"
end
verify_group = request_apple("GET", "/v1/betaGroups/#{group_id}/relationships/builds?limit=200", token).fetch("data", [])
abort("Failed to verify build 9 tester assignment") unless verify_group.any? { |b| b["id"] == build_id }
detail_after = request_apple("GET", "/v1/builds/#{build_id}/buildBetaDetail", token)
after = detail_after.fetch("data", {}).fetch("attributes", {})
puts "BETA_VERIFIED build=#{BUILD_NUMBER} group=Testers internal=#{after['internalBuildState']} external=#{after['externalBuildState']}"
puts "CIPHERVAULT_BUILD_9_COMPLIANCE_FIX_COMPLETE"
