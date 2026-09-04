#!/usr/bin/env ruby
# frozen_string_literal: true

# Rebuilds data/steam_countries.json and data/steam_countries.min.json by
# crawling Steam's location tree:
#
#   /actions/QueryLocations//        -> countries
#   /actions/QueryLocations/CC       -> states of country CC
#   /actions/QueryLocations/CC/SC    -> cities of state SC in country CC
#
# Any node can be a leaf: a country without states, or a state without
# cities. Steam signals "no children" with an HTTP 400 response whose body
# is the literal string "null", so that is treated as an empty list rather
# than an error.
#
# Existing coordinates/coordinates_accuracy_level fields (added by hand in
# the past, Steam's API does not provide them) are preserved for any
# country/state/city code that still exists after the crawl. Codes that no
# longer exist are dropped, and newly discovered codes are left without
# coordinates.
#
# Usage:
#   ruby script/update_locations.rb [--concurrency N] [--country CC]

require 'net/http'
require 'json'
require 'uri'
require 'optparse'

BASE_URL = 'https://steamcommunity.com/actions/QueryLocations'
USER_AGENT = 'steam-friends-countries-crawler (+https://github.com/holek/steam-friends-countries)'
MAX_ATTEMPTS = 4
RETRY_BACKOFF = 1.5

# Raised when a node's children could not be determined at all (as opposed
# to a confirmed-empty node, which fetch() reports as nil). This must never
# be silently treated as "no children" - Steam can 403 a burst of requests
# under load, and a state with real cities looks identical to an empty one
# once you give up and shrug.
class FetchError < StandardError; end

DATA_DIR = File.expand_path('../data', __dir__)
FULL_JSON_PATH = File.join(DATA_DIR, 'steam_countries.json')
MIN_JSON_PATH = File.join(DATA_DIR, 'steam_countries.min.json')

options = { concurrency: 8, country: nil }
OptionParser.new do |opts|
  opts.on('--concurrency N', Integer, 'Number of parallel requests (default 8)') { |n| options[:concurrency] = n }
  opts.on('--country CC', String, 'Only crawl this one country code (for testing)') { |c| options[:country] = c.upcase }
end.parse!

# Runs `items.size` jobs across a pool of threads, each with its own
# keep-alive HTTP connection, and returns results in the original order.
def run_pool(items, concurrency)
  results = Array.new(items.size)
  queue = Queue.new
  items.each_with_index { |item, i| queue << [item, i] }
  concurrency.times { queue << nil }

  mutex = Mutex.new
  done = 0

  workers = concurrency.times.map do
    Thread.new do
      uri = URI.parse(BASE_URL)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) do |http|
        while (job = queue.pop)
          item, index = job
          results[index] =
            begin
              yield(http, item)
            rescue FetchError => e
              e
            end
          mutex.synchronize do
            done += 1
            print("\r  #{done}/#{items.size}")
            $stdout.flush
          end
        end
      end
    end
  end
  workers.each(&:join)
  puts
  results
end

# GET a QueryLocations path. Returns the parsed JSON array on success, or
# nil if Steam reports this node has no children (HTTP 400 / body "null").
def fetch(http, path)
  uri = URI.parse("#{BASE_URL}#{path}")
  attempt = 0
  begin
    attempt += 1
    request = Net::HTTP::Get.new(uri.request_uri)
    request['User-Agent'] = USER_AGENT
    response = http.request(request)
    case response.code.to_i
    when 200
      JSON.parse(response.body)
    when 400
      nil
    else
      raise "unexpected HTTP #{response.code}"
    end
  rescue StandardError => e
    if attempt < MAX_ATTEMPTS
      sleep(RETRY_BACKOFF * attempt)
      retry
    else
      raise FetchError, "#{path}: #{e.message}"
    end
  end
end

# Retries, one request at a time with a long pause between them, any job
# whose result is a FetchError from the (parallel) first pass. Parallel
# bursts are what triggered Steam's rate limiting in the first place, so
# recovery has to be slow and serial. Mutates `results` in place.
def serial_retry(jobs, results)
  failed_indexes = results.each_index.select { |i| results[i].is_a?(FetchError) }
  return if failed_indexes.empty?

  warn "Retrying #{failed_indexes.size} request(s) that failed earlier, one at a time..."
  base_host = URI.parse(BASE_URL).host
  Net::HTTP.start(base_host, 443, use_ssl: true, open_timeout: 10, read_timeout: 20) do |http|
    failed_indexes.each do |i|
      sleep 5
      results[i] =
        begin
          yield(http, jobs[i])
        rescue FetchError => e
          warn "  still failing: #{e.message}"
          e
        end
    end
  end
end

def abort_on_errors!(results, label)
  errors = results.select { |r| r.is_a?(FetchError) }
  return if errors.empty?

  warn "\nAborting: #{errors.size} #{label} request(s) never succeeded, refusing to write data with gaps:"
  errors.each { |e| warn "  #{e.message}" }
  exit 1
end

def load_old_tree
  JSON.parse(File.read(FULL_JSON_PATH))
rescue Errno::ENOENT, JSON::ParserError
  {}
end

def carry_over_coordinates(node, old_node)
  return unless old_node && old_node['coordinates']

  node['coordinates'] = old_node['coordinates']
  node['coordinates_accuracy_level'] = old_node['coordinates_accuracy_level']
end

old_tree = load_old_tree

puts 'Fetching country list...'
base_host = URI.parse(BASE_URL).host
countries = Net::HTTP.start(base_host, 443, use_ssl: true) { |http| fetch(http, '//') } || []
countries.select! { |c| c['countrycode'] == options[:country] } if options[:country]
puts "  #{countries.size} countries"

fetch_states = ->(http, country) { fetch(http, "/#{country['countrycode']}") || [] }
fetch_cities = ->(http, state) { fetch(http, "/#{state['countrycode']}/#{state['statecode']}") || [] }

puts 'Fetching states for each country...'
country_states = run_pool(countries, options[:concurrency], &fetch_states)
serial_retry(countries, country_states, &fetch_states)
abort_on_errors!(country_states, 'state-list')

state_jobs = []
countries.each_with_index do |country, i|
  country_states[i].each { |state| state_jobs << state }
end

puts 'Fetching cities for each state...'
state_cities = run_pool(state_jobs, options[:concurrency], &fetch_cities)
serial_retry(state_jobs, state_cities, &fetch_cities)
abort_on_errors!(state_cities, 'city-list')

cities_by_country_state = Hash.new { |h, k| h[k] = {} }
state_jobs.each_with_index do |state, i|
  cities_by_country_state[[state['countrycode'], state['statecode']]] = state_cities[i]
end

puts 'Assembling tree...'
tree = {}
countries.each_with_index do |country, i|
  cc = country['countrycode']
  old_country = old_tree[cc]

  states = {}
  country_states[i].sort_by { |s| s['statecode'] }.each do |state|
    sc = state['statecode']
    old_state = old_country && old_country['states'] && old_country['states'][sc]

    cities = {}
    cities_by_country_state[[cc, sc]].sort_by { |c| c['cityid'] }.each do |city|
      cid = city['cityid'].to_s
      old_city = old_state && old_state['cities'] && old_state['cities'][cid]

      city_node = { 'name' => city['cityname'] }
      carry_over_coordinates(city_node, old_city)
      cities[cid] = city_node
    end

    state_node = { 'name' => state['statename'], 'cities' => cities }
    carry_over_coordinates(state_node, old_state)
    states[sc] = state_node
  end

  country_node = { 'name' => country['countryname'], 'states' => states }
  carry_over_coordinates(country_node, old_country)
  tree[cc] = country_node
end

sorted_tree = tree.sort.to_h

if options[:country]
  puts JSON.pretty_generate(sorted_tree, indent: '    ')
else
  File.write(FULL_JSON_PATH, JSON.pretty_generate(sorted_tree, indent: '    '))
  File.write(MIN_JSON_PATH, JSON.generate(sorted_tree))
  puts "Wrote #{FULL_JSON_PATH}"
  puts "Wrote #{MIN_JSON_PATH}"
end
