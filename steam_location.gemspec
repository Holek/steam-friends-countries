Gem::Specification.new do |s|
  s.name        = 'steam_location'
  s.version     = '0.3.0'
  s.date        = '2026-09-05'
  s.summary     = "Steam Friends' Location"
  s.description = "This gem allows you to parse Steam Community's player location and get a proper name for their location."
  s.authors     = ["Mike Połtyn"]
  s.email       = 'mike@poltyn.com'
  s.files       = ['data/steam_countries.json', 'data/steam_countries.min.json', 'lib/steam_location.rb']
  s.require_paths = ["lib"]
end
