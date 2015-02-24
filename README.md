steam-friends-countries [![Gem Version](https://badge.fury.io/rb/steam_location.svg)](http://badge.fury.io/rb/steam_location)
=======================

Steam Community city data in JSON format. [Steam Community](http://steamcommunity.com) is a great social network for gamers. It's also a very good network to base your social projects on.

Unfortunately, the API is not one of the best. While it's [documented well](http://steamcommunity.com/dev) for the most part, it still lacks in some figurative data.

One of this data is [information about players' locations](https://developer.valvesoftware.com/wiki/Steam_Web_API#GetPlayerSummaries_.28v0001.29). It's presented in a form of three keys:

    "loccountrycode"=>"PL",
    "locstatecode"=>"86",
    "loccityid"=>35924

which corresponds to... Yeah, exactly what? We know `PL` stands for Poland, but what about `"86"`? What about `35924`?

Notice how inconsistent this data is:

1. State code always is returned as a stringified number. Very rarely it corresponds to something like `"M3"` (it happens, though)
2. Location city ID is just that. It's just an ID of a city. No indication what city, where, nothing, just a plain number

Solution
========

Well, I've devised a solution. I've scraped all the information about countries, states and cities and provided it in a simple JSON, machine-readable file, so you can check people's location on your own!

The file is available in the repository and, obviously, free and open-source.


Installation and usage
======================

### As a JSON

There are plain JSON files with all the locations with IDs and name loccated in [`/data`](data/) folder. If you don't want to use this data in a gem, you can simply grab the JSON files and do some magic of your own on them.

### As a gem

    gem install steam_location

or add to `Gemfile`

    gem "steam_location", "~> 0.1.0"

Quick tutorial (for IRB):

    > require 'steam_location'
    > location = {"loccountrycode"=>"PL", "locstatecode"=>"86", "loccityid"=>35924}
    > SteamLocation.find(location)
     => => {:map_search_string=>"Poznan, Wielkopolskie, Poland", :coordinates_accuracy_level=>"city", :locstate=>"Wielkopolskie", :loccountry=>"Poland", :loccity=>"Poznan", :coordinates=>"52.406374,16.925168"}
    > SteamLocation.find("PL", "86", 35924)
     => => {:map_search_string=>"Poznan, Wielkopolskie, Poland", :coordinates_accuracy_level=>"city", :locstate=>"Wielkopolskie", :loccountry=>"Poland", :loccity=>"Poznan", :coordinates=>"52.406374,16.925168"}

The `location` hash in the example is an actual part of Steam Web API response for [`GetPlayerSummaries`](https://developer.valvesoftware.com/w/index.php?title=Steam_Web_API&oldid=174392#GetPlayerSummaries_.28v0002.29) call. You can simply pass player info hash to `SteamLocation.find` method, and it'll return information about player location.

You can use `:map_search_string` for map search queries, like asking Google Maps or Microsoft Bing or whatever mapping system you want to use.

This gem has been tested against Ruby 1.8.7, 1.9.2 and 1.9.3.

Changelog
=========

* v0.1.0 - *location data is correct from this point on*
  * fixed Colorado, US' cities
  * fixed Mexico city duplication
  * fixed Finland information
* v0.0.2
  * fixed German state names
* v0.0.1
  * initial version

Thanks
=======

Special thanks go to <b>[@stephanpavlovic](https://github.com/stephanpavlovic)</b> for helping out with a scraper script!

LICENSE
=======

    * ----------------------------------------------------------------------------
    * "THE BEER-WARE LICENSE" (Revision 1):
    * <holek@derpymail.org> wrote this file. As long as you retain this notice you
    * can do whatever you want with this stuff. If we meet some day, and you think
    * this stuff is worth it, you can buy me a beer in return -- Mike Połtyn
    * ----------------------------------------------------------------------------
