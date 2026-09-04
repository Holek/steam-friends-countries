#!/usr/bin/env ruby
# frozen_string_literal: true

# Backfills missing coordinates/coordinates_accuracy_level fields in
# data/steam_countries.json using OpenStreetMap's Nominatim geocoder.
# Steam's API (crawled by script/update_locations.rb) carries no coordinate
# data of its own - existing coordinates were added by hand years ago, and
# this fills the gaps left by newly-discovered or never-geocoded codes.
# Existing coordinates are never touched, only missing ones are filled in.
#
# Nominatim's public instance caps usage at roughly 1 request/second and
# forbids parallel requests, so this runs strictly sequentially - unlike
# script/update_locations.rb, there is no thread pool here.
#
# Query strategy, evidence-based (tested against the real gaps by hand
# before writing this):
#   - Country level: structured `country=<ISO code>` is far more reliable
#     than Steam's official ISO long-form name (eg. "Korea, Democratic
#     People's Republic of" matches nothing, but the code "KP" finds North
#     Korea's real boundary). Falls back to a free-text search on the
#     stored country name as-is - never split or rephrase it, since that
#     both risks a wrong match (eg. "Heard" alone, split out of "Heard &
#     McDonald Islands", matches a US county) and accepting a same-typed
#     but irrelevant hit (eg. "Saint Martin (French part)" literally
#     matches a maritime boundary line at very low importance). Both are
#     guarded against by requiring class=="boundary" and importance high
#     enough to be a real place, not overlappable in the DB, rather than
#     a technicality match.
#   - State/city level: bare free-text search is not used at all - it
#     matched a convenience shop in Transnistria for a country query once
#     during testing. Only structured country=/state=/city= fields are
#     used, since Nominatim matches those against actual address
#     components rather than doing a blind text search.
#   - Any level that still can't be resolved falls back to its parent's
#     already-resolved coordinates with a downgraded accuracy level - the
#     same convention the original hand-curated data already uses.
#
# Usage:
#   ruby script/update_coordinates.rb [--country CC] [--interval SECONDS] [--dry-run] [--limit N]

require 'net/http'
require 'json'
require 'uri'
require 'optparse'

BASE_URL = 'https://nominatim.openstreetmap.org/search'
USER_AGENT = 'steam-friends-countries-geocoder (+https://github.com/holek/steam-friends-countries)'
MAX_ATTEMPTS = 4
RETRY_BACKOFF = 2.0
MIN_IMPORTANCE = 0.3

DATA_DIR = File.expand_path('../data', __dir__)
FULL_JSON_PATH = File.join(DATA_DIR, 'steam_countries.json')
MIN_JSON_PATH = File.join(DATA_DIR, 'steam_countries.min.json')

# Raised when a Nominatim request never succeeds at all. This must never be
# treated as "no match" - conflating "couldn't ask" with "asked and there's
# nothing there" is exactly what caused script/update_locations.rb to
# almost silently wipe out real data during its own rate-limit incident.
class GeocodeError < StandardError; end

options = { interval: 1.1, country: nil, dry_run: false, limit: nil }
OptionParser.new do |opts|
  opts.on('--country CC', String, 'Only process this one country code') { |c| options[:country] = c.upcase }
  opts.on('--interval SECONDS', Float, 'Delay between requests (default 1.1)') { |n| options[:interval] = n }
  opts.on('--dry-run', "Print what would change without writing files") { options[:dry_run] = true }
  opts.on('--limit N', Integer, 'Stop after N nodes processed (smoke test)') { |n| options[:limit] = n }
end.parse!

# GET Nominatim's structured search with the given params. Returns the
# parsed JSON array - possibly empty, which is a confirmed "no match", not
# an error. Raises GeocodeError if the request itself never succeeds.
def search(http, params)
  uri = URI.parse(BASE_URL)
  uri.query = URI.encode_www_form(params.merge('format' => 'json', 'limit' => '1'))
  attempt = 0
  begin
    attempt += 1
    request = Net::HTTP::Get.new(uri.request_uri)
    request['User-Agent'] = USER_AGENT
    response = http.request(request)
    raise "unexpected HTTP #{response.code}" unless response.code.to_i == 200

    JSON.parse(response.body)
  rescue StandardError => e
    if attempt < MAX_ATTEMPTS
      sleep(RETRY_BACKOFF * attempt)
      retry
    else
      raise GeocodeError, "#{params}: #{e.message}"
    end
  end
end

def coordinates_from(result)
  "#{result['lat']},#{result['lon']}"
end

def plausible_boundary?(result)
  result['class'] == 'boundary' && result['importance'].to_f > MIN_IMPORTANCE
end

# Returns [coordinates, accuracy_level] or nil.
def geocode_country(http, cc, name, interval)
  sleep interval
  results = search(http, 'country' => cc)
  return [coordinates_from(results.first), 'country'] unless results.empty?

  sleep interval
  results = search(http, 'q' => name)
  return [coordinates_from(results.first), 'country'] if !results.empty? && plausible_boundary?(results.first)

  nil
end

def geocode_state(http, cc, state_name, interval)
  sleep interval
  results = search(http, 'country' => cc, 'state' => state_name)
  return nil if results.empty?

  [coordinates_from(results.first), 'state']
end

def geocode_city(http, cc, state_name, city_name, interval)
  sleep interval
  results = search(http, 'country' => cc, 'state' => state_name, 'city' => city_name)
  return [coordinates_from(results.first), 'city'] unless results.empty?

  sleep interval
  results = search(http, 'country' => cc, 'city' => city_name)
  return [coordinates_from(results.first), 'city'] unless results.empty?

  nil
end

tree = JSON.parse(File.read(FULL_JSON_PATH))
countries = options[:country] ? tree.select { |cc, _| cc == options[:country] } : tree

processed = 0
limit_reached = -> { options[:limit] && processed >= options[:limit] }

uri = URI.parse(BASE_URL)
Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) do |http|
  countries.each do |cc, country|
    next if limit_reached.call

    changed = false

    unless country['coordinates']
      if (result = geocode_country(http, cc, country['name'], options[:interval]))
        country['coordinates'], country['coordinates_accuracy_level'] = result
        changed = true
        puts "#{cc}: country -> #{result.first} (#{result.last})"
      else
        warn "#{cc}: country -- no match, leaving blank"
      end
      processed += 1
    end

    country.fetch('states', {}).each do |sc, state|
      next if limit_reached.call

      unless state['coordinates']
        result = geocode_state(http, cc, state['name'], options[:interval])
        result ||= [country['coordinates'], 'country'] if country['coordinates']
        if result
          state['coordinates'], state['coordinates_accuracy_level'] = result
          changed = true
          puts "#{cc}/#{sc}: state -> #{result.first} (#{result.last})"
        end
        processed += 1
      end

      state.fetch('cities', {}).each do |cid, city|
        next if limit_reached.call || city['coordinates']

        result = geocode_city(http, cc, state['name'], city['name'], options[:interval])
        result ||= [state['coordinates'], state['coordinates_accuracy_level']] if state['coordinates']
        result ||= [country['coordinates'], 'country'] if country['coordinates']
        if result
          city['coordinates'], city['coordinates_accuracy_level'] = result
          changed = true
          puts "#{cc}/#{sc}/#{cid}: city -> #{result.first} (#{result.last})"
        end
        processed += 1
      end
    end

    next unless changed && !options[:dry_run]

    File.write(FULL_JSON_PATH, JSON.pretty_generate(tree, indent: '    '))
    File.write(MIN_JSON_PATH, JSON.generate(tree))
  end
end

puts "Done. Processed #{processed} node(s)."
