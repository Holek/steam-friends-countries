require 'json'
module SteamLocation
  @@countries = JSON.parse(File.open(File.expand_path(File.join(File.dirname(__FILE__), '..', 'data', 'steam_countries.min.json'))).read)

  def self.find(loccountrycode, locstatecode = nil, loccityid = nil)
    if loccountrycode.is_a?(Hash)
      params = loccountrycode.dup
      loccityid = params['loccityid']
      locstatecode = params['locstatecode']
      loccountrycode = params['loccountrycode']
    end
    result = {}
    map_search_array = []
    country = @@countries[loccountrycode.to_s]
    if country
      map_search_array.unshift(result[:loccountry] = country['name'])
      result[:coordinates] = country['coordinates']
      result[:coordinates_accuracy_level] = country['coordinates_accuracy_level']
      if state = country['states'][locstatecode.to_s]
        map_search_array.unshift(result[:locstate] = state['name'])
        if state['coordinates']
          result[:coordinates] = state['coordinates']
          result[:coordinates_accuracy_level] = state['coordinates_accuracy_level']
        end
        if city = state['cities'][loccityid.to_s]
          map_search_array.unshift(result[:loccity] = city['name'])
          if city['coordinates']
            result[:coordinates] = city['coordinates']
            result[:coordinates_accuracy_level] = city['coordinates_accuracy_level']
          end
        end
      end
      result[:map_search_string] = map_search_array.join(', ')
      result
    end
  ensure
    (loccountrycode = params) if params
  end
end
