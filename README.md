steam-friends-countries
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
