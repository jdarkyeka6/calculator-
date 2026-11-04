#!/usr/bin/env ruby
# Read-only Apple signing inventory. Do not alter Apple certificates or profiles.
require "json"
require "jwt"
require "openssl"
require "net/http"
require "uri"
require "base64"
require "time"

def required_secret(name)
  value = ENV[name].to_s.strip
  abort("Missing #{name}") if value.empty?
  value
end

key_id = required_secret("ASC_KEY_ID")
issuer_id = required_secret("ASC_ISSUER_ID")
key_source = required_secret("ASC_PRIVATE_KEY")
pem = if key_source.include?("BEGIN PRIVATE KEY")
  key_source.gsub("\\n", "\n")
else
  Base64.strict_decode64(key_source.gsub(/\s/, ""))
end
now = Time.now.to_i
payload = {iss: issuer_id, iat: now - 20, exp: now + 900, aud: "appstoreconnect-v1"}
token = JWT.encode(payload, OpenSSL::PKey.read(pem), "ES256", {kid: key_id, typ: "JWT"})

def fetch_pages(url, token)
  results = []
  included = []
  10.times do
    raise "Unexpected API endpoint" unless URI(url).host == "api.appstoreconnect.apple.com"
    uri = URI(url)
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Accept"] = "application/json"
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
    unless response.code == "200"
      warn "Apple API #{uri.path} returned HTTP #{response.code}: #{response.body.to_s[0, 250]}"
      exit 2
    end
    result = JSON.parse(response.body)
    results.concat(result.fetch("data", []))
    included.concat(result.fetch("included", []))
    url = result.dig("links", "next")
    return [results, included] if url.nil? || url.empty?
  end
  raise "More than 10 pages; refusing to classify incomplete inventory"
end

certificates, _ = fetch_pages("https://api.appstoreconnect.apple.com/v1/certificates?limit=200", token)
profiles, related = fetch_pages("https://api.appstoreconnect.apple.com/v1/profiles?limit=200&include=certificates,bundleId", token)

bundle_names = related.select { |obj| obj["type"] == "bundleIds" }.to_h do |obj|
  [obj["id"], obj.dig("attributes", "identifier") || obj.dig("attributes", "name")]
end

puts "=== APPLE DISTRIBUTION CERTIFICATE READ-ONLY AUDIT ==="
puts "Certificates returned: #{certificates.length}; profiles returned: #{profiles.length}"
certificates.each do |cert|
  attrs = cert.fetch("attributes", {})
  type = attrs["certificateType"].to_s
  next unless type.include?("DISTRIBUTION")
  id = cert.fetch("id")
  matching = profiles.select do |profile|
    rel = profile.dig("relationships", "certificates", "data") || []
    rel.any? { |ref| ref["id"] == id }
  end
  active = matching.select { |profile| profile.dig("attributes", "profileState") == "ACTIVE" }
  puts "CERT id=#{id} type=#{type} expires=#{attrs["expirationDate"]} activated=#{attrs["activated"]}"
  puts "  profile_count=#{matching.length}, active_profile_count=#{active.length}"
  matching.first(12).each do |profile|
    bundle_id = profile.dig("relationships", "bundleId", "data", "id")
    app = bundle_names[bundle_id] || "unknown"
    state = profile.dig("attributes", "profileState")
    puts "  PROFILE state=#{state} app=#{app} type=#{profile.dig("attributes", "profileType")}"
  end
  puts "  EXTRA_PROFILES=#{matching.length - 12}" if matching.length > 12
  puts "  WARNING: No linked profiles does NOT prove a certificate is unused."
end
puts "AUDIT_COMPLETE_READ_ONLY"
