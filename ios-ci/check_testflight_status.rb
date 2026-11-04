#!/usr/bin/env ruby
# Inspect only the state of CipherVault's App Store Connect uploads and builds.
# This tool never creates, edits, sends invitations, or deletes Apple resources.
require "json"
require "jwt"
require "openssl"
require "net/http"
require "uri"
require "base64"

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
  OpenSSL::PKey.read(pem),
  "ES256", {kid: secret("ASC_KEY_ID"), typ: "JWT"}
)

def read_apple(endpoint, token)
  url = URI("https://api.appstoreconnect.apple.com" + endpoint)
  raise "Unexpected host" unless url.host == "api.appstoreconnect.apple.com"
  req = Net::HTTP::Get.new(url)
  req["Authorization"] = "Bearer #{token}"
  req["Accept"] = "application/json"
  res = Net::HTTP.start(url.host, url.port, use_ssl: true, open_timeout: 15, read_timeout: 30) { |http| http.request(req) }
  unless res.code == "200"
    puts "API_ERROR endpoint=#{endpoint.split('?').first} http=#{res.code} details=#{res.body.to_s[0, 350]}"
    return nil
  end
  JSON.parse(res.body)
end

app_response = read_apple("/v1/apps?filter%5BbundleId%5D=com.jdarkyeka6.calculator&limit=10", token)
abort("Unable to query App Store Connect apps") if app_response.nil?
app = app_response.fetch("data", []).find { |a| a.dig("attributes", "bundleId") == "com.jdarkyeka6.calculator" }
abort("APP_NOT_FOUND for com.jdarkyeka6.calculator") unless app
id = app.fetch("id")
puts "CIPHERVAULT_APP id=#{id} name=#{app.dig('attributes','name')} bundle=com.jdarkyeka6.calculator"

uploads = read_apple("/v1/apps/#{id}/buildUploads?limit=30&sort=-uploadedDate", token)
if uploads
  rows = uploads.fetch("data", [])
  puts "BUILD_UPLOADS_TOTAL_FIRST_PAGE=#{rows.size}"
  rows.first(12).each do |u|
    a = u.fetch("attributes", {})
    state = a["state"].is_a?(Hash) ? a["state"]["state"] : a["state"]
    puts "UPLOAD version=#{a['cfBundleShortVersionString']} build=#{a['cfBundleVersion']} status=#{state} date=#{a['uploadedDate']} details=#{a['state'].is_a?(Hash) ? a['state']['errors'] : ''}"
  end
end

builds = read_apple("/v1/apps/#{id}/builds?limit=30", token)
if builds
  rows = builds.fetch("data", [])
  puts "BUILDS_TOTAL_FIRST_PAGE=#{rows.size}"
  rows.first(12).each do |b|
    a = b.fetch("attributes", {})
    puts "BUILD id=#{b['id']} build=#{a['version']} processing=#{a['processingState']} uploaded=#{a['uploadedDate']} encryption=#{a['usesNonExemptEncryption'].inspect}"
    detail = read_apple("/v1/builds/#{b.fetch('id')}/buildBetaDetail", token)
    if detail
      d = detail.fetch("data", {})
      d = d.first if d.is_a?(Array)
      beta = d&.fetch("attributes", {}) || {}
      puts "BETA build=#{a['version']} internal=#{beta['internalBuildState']} external=#{beta['externalBuildState']}"
    end
  end
end
groups = read_apple("/v1/apps/#{id}/betaGroups?limit=30", token)
if groups
  group_rows = groups.fetch("data", [])
  puts "BETA_GROUPS_TOTAL_FIRST_PAGE=#{group_rows.size}"
  group_rows.each do |group|
    a = group.fetch("attributes", {})
    puts "BETA_GROUP id=#{group['id']} name=#{a['name']} internal=#{a['isInternalGroup']} publicLink=#{a['publicLinkEnabled']}"
  end
end
puts "CIPHERVAULT_READ_ONLY_CHECK_COMPLETE"
