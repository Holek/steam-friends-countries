# Reading `data/steam_countries.json` directly

The [`data/steam_countries.json`](data/steam_countries.json) file (and its minified
twin, [`data/steam_countries.min.json`](data/steam_countries.min.json)) is the core of
this package. You don't need the Ruby gem to use it — it's plain JSON, so any language
with a JSON parser can look up a Steam location on its own.

This file shows how, in 15+ languages, using each language's most common JSON library.

## The problem these examples solve

[`GetPlayerSummaries`](https://developer.valvesoftware.com/wiki/Steam_Web_API#GetPlayerSummaries_(v0002))
returns a player's location as up to three keys:

```json
{"loccountrycode": "PL", "locstatecode": "86", "loccityid": 35924}
```

Steam sends all three keys only when it knows all three. In practice you get one of
three shapes:

1. **Country only** — `loccountrycode` is present, `locstatecode`/`loccityid` are absent.
2. **Country + state** — `loccountrycode` and `locstatecode` are present, `loccityid` is absent.
3. **Country + state + city** — all three keys are present.

Every example below implements one `find_location` function that handles all three
cases through optional parameters, then calls it three times to show each case. All
three calls use the same real record — Poland (`PL`) / Wielkopolskie (`86`) / Poznań
(`35924`) — the same one used in the main [README](README.md), so the outputs below are
easy to compare across languages.

## The lookup rule

Every node in the file (country, state, city) may carry its own `coordinates` and
`coordinates_accuracy_level`. A node that has no state-specific or city-specific
coordinates on file simply doesn't have those keys. So the rule, from most to least
specific:

1. Start from the country's `coordinates` (if the country has one).
2. If a state resolves **and has its own `coordinates`**, use those instead.
3. If a city resolves **and has its own `coordinates`**, use those instead.

This is the same rule [`lib/steam_location.rb`](lib/steam_location.rb) uses, so a raw
JSON lookup and the gem agree on the answer.

## Two things every example handles

- **`locstatecode` is always a string** in Steam's response (e.g. `"86"`), but JSON
  object keys are always strings anyway, so this needs no conversion.
- **`loccityid` is a number** in Steam's response (e.g. `35924`, not `"35924"`), but the
  `cities` object in the JSON file is keyed by the *string* `"35924"`. Every example
  below converts the city id to a string before using it as a lookup key — skip that
  step and the lookup silently returns nothing.

All examples assume they run from the repository root, so `data/steam_countries.json`
resolves correctly as a relative path.

---

## JavaScript (Node.js built-in `JSON`)

```javascript
const fs = require("fs");

const countries = JSON.parse(fs.readFileSync("data/steam_countries.json", "utf8"));

function findLocation(countryCode, stateCode = null, cityId = null) {
  const country = countries[countryCode];
  if (!country) return null;

  const state = stateCode !== null ? country.states[String(stateCode)] : null;
  const city = state && cityId !== null ? state.cities[String(cityId)] : null;

  let coordinates = country.coordinates;
  let accuracy = country.coordinates_accuracy_level;
  if (state && state.coordinates) {
    coordinates = state.coordinates;
    accuracy = state.coordinates_accuracy_level;
  }
  if (city && city.coordinates) {
    coordinates = city.coordinates;
    accuracy = city.coordinates_accuracy_level;
  }

  return {
    loccountry: country.name,
    locstate: state ? state.name : null,
    loccity: city ? city.name : null,
    coordinates,
    coordinates_accuracy_level: accuracy,
    map_search_string: [city, state, country].filter(Boolean).map((n) => n.name).join(", "),
  };
}

console.log("Case 1:", findLocation("PL"));
console.log("Case 2:", findLocation("PL", "86"));
console.log("Case 3:", findLocation("PL", "86", 35924));
```

Output (verified against this run of the file):

```
Case 1: { loccountry: 'Poland', locstate: null, loccity: null, coordinates: '51.91943800000001,19.145136', coordinates_accuracy_level: 'country', map_search_string: 'Poland' }
Case 2: { loccountry: 'Poland', locstate: 'Wielkopolskie', loccity: null, coordinates: '52.279986,17.352294', coordinates_accuracy_level: 'state', map_search_string: 'Wielkopolskie, Poland' }
Case 3: { loccountry: 'Poland', locstate: 'Wielkopolskie', loccity: 'Poznan', coordinates: '52.406374,16.925168', coordinates_accuracy_level: 'city', map_search_string: 'Poznan, Wielkopolskie, Poland' }
```

## TypeScript (same runtime `JSON`, typed)

```typescript
import * as fs from "fs";

interface CityData {
  name: string;
  coordinates?: string;
  coordinates_accuracy_level?: string;
}
interface StateData {
  name: string;
  cities: Record<string, CityData>;
  coordinates?: string;
  coordinates_accuracy_level?: string;
}
interface CountryData {
  name: string;
  states: Record<string, StateData>;
  coordinates?: string;
  coordinates_accuracy_level?: string;
}
interface Location {
  loccountry: string;
  locstate?: string;
  loccity?: string;
  coordinates?: string;
  coordinates_accuracy_level?: string;
  map_search_string: string;
}

const countries: Record<string, CountryData> = JSON.parse(
  fs.readFileSync("data/steam_countries.json", "utf8")
);

function findLocation(countryCode: string, stateCode?: string, cityId?: number): Location | null {
  const country = countries[countryCode];
  if (!country) return null;

  const state = stateCode !== undefined ? country.states[stateCode] : undefined;
  const city = state && cityId !== undefined ? state.cities[String(cityId)] : undefined;

  let coordinates = country.coordinates;
  let accuracy = country.coordinates_accuracy_level;
  if (state?.coordinates) {
    coordinates = state.coordinates;
    accuracy = state.coordinates_accuracy_level;
  }
  if (city?.coordinates) {
    coordinates = city.coordinates;
    accuracy = city.coordinates_accuracy_level;
  }

  const parts = [city?.name, state?.name, country.name].filter((n): n is string => Boolean(n));

  return {
    loccountry: country.name,
    locstate: state?.name,
    loccity: city?.name,
    coordinates,
    coordinates_accuracy_level: accuracy,
    map_search_string: parts.join(", "),
  };
}

console.log("Case 1:", findLocation("PL"));
console.log("Case 2:", findLocation("PL", "86"));
console.log("Case 3:", findLocation("PL", "86", 35924));
```

Output: identical to the JavaScript example above — TypeScript compiles to the same
`JSON.parse` call, the types just catch mistakes (like forgetting `String(cityId)`) at
compile time.

## Python (`json`, standard library)

```python
import json

with open("data/steam_countries.json", encoding="utf-8") as f:
    countries = json.load(f)


def find_location(country_code, state_code=None, city_id=None):
    country = countries.get(country_code)
    if country is None:
        return None

    state = country["states"].get(str(state_code)) if state_code is not None else None
    city = state["cities"].get(str(city_id)) if state and city_id is not None else None

    coordinates = country.get("coordinates")
    accuracy = country.get("coordinates_accuracy_level")
    if state and state.get("coordinates"):
        coordinates, accuracy = state["coordinates"], state["coordinates_accuracy_level"]
    if city and city.get("coordinates"):
        coordinates, accuracy = city["coordinates"], city["coordinates_accuracy_level"]

    parts = [n["name"] for n in (city, state, country) if n]
    return {
        "loccountry": country["name"],
        "locstate": state["name"] if state else None,
        "loccity": city["name"] if city else None,
        "coordinates": coordinates,
        "coordinates_accuracy_level": accuracy,
        "map_search_string": ", ".join(parts),
    }


print("Case 1:", find_location("PL"))
print("Case 2:", find_location("PL", "86"))
print("Case 3:", find_location("PL", "86", 35924))
```

Output (verified):

```
Case 1: {'loccountry': 'Poland', 'locstate': None, 'loccity': None, 'coordinates': '51.91943800000001,19.145136', 'coordinates_accuracy_level': 'country', 'map_search_string': 'Poland'}
Case 2: {'loccountry': 'Poland', 'locstate': 'Wielkopolskie', 'loccity': None, 'coordinates': '52.279986,17.352294', 'coordinates_accuracy_level': 'state', 'map_search_string': 'Wielkopolskie, Poland'}
Case 3: {'loccountry': 'Poland', 'locstate': 'Wielkopolskie', 'loccity': 'Poznan', 'coordinates': '52.406374,16.925168', 'coordinates_accuracy_level': 'city', 'map_search_string': 'Poznan, Wielkopolskie, Poland'}
```

## Ruby (`json`, standard library)

This is the same logic [`lib/steam_location.rb`](lib/steam_location.rb) uses internally
— shown here against the raw file, without installing the gem.

```ruby
require "json"

countries = JSON.parse(File.read("data/steam_countries.json"))

def find_location(countries, country_code, state_code = nil, city_id = nil)
  country = countries[country_code]
  return nil unless country

  state = country["states"][state_code.to_s] if state_code
  city = state["cities"][city_id.to_s] if state && city_id

  coordinates = country["coordinates"]
  accuracy = country["coordinates_accuracy_level"]
  if state && state["coordinates"]
    coordinates, accuracy = state["coordinates"], state["coordinates_accuracy_level"]
  end
  if city && city["coordinates"]
    coordinates, accuracy = city["coordinates"], city["coordinates_accuracy_level"]
  end

  {
    loccountry: country["name"],
    locstate: state && state["name"],
    loccity: city && city["name"],
    coordinates: coordinates,
    coordinates_accuracy_level: accuracy,
    map_search_string: [city, state, country].compact.map { |n| n["name"] }.join(", "),
  }
end

p find_location(countries, "PL")
p find_location(countries, "PL", "86")
p find_location(countries, "PL", "86", 35924)
```

Output (verified):

```
{:loccountry=>"Poland", :locstate=>nil, :loccity=>nil, :coordinates=>"51.91943800000001,19.145136", :coordinates_accuracy_level=>"country", :map_search_string=>"Poland"}
{:loccountry=>"Poland", :locstate=>"Wielkopolskie", :loccity=>nil, :coordinates=>"52.279986,17.352294", :coordinates_accuracy_level=>"state", :map_search_string=>"Wielkopolskie, Poland"}
{:loccountry=>"Poland", :locstate=>"Wielkopolskie", :loccity=>"Poznan", :coordinates=>"52.406374,16.925168", :coordinates_accuracy_level=>"city", :map_search_string=>"Poznan, Wielkopolskie, Poland"}
```

## PHP (`json_decode`, built-in)

```php
<?php

$countries = json_decode(file_get_contents("data/steam_countries.json"), true);

function findLocation(array $countries, string $countryCode, ?string $stateCode = null, ?int $cityId = null): ?array
{
    $country = $countries[$countryCode] ?? null;
    if ($country === null) {
        return null;
    }

    $state = $stateCode !== null ? ($country["states"][$stateCode] ?? null) : null;
    $city = ($state !== null && $cityId !== null) ? ($state["cities"][(string) $cityId] ?? null) : null;

    $coordinates = $country["coordinates"] ?? null;
    $accuracy = $country["coordinates_accuracy_level"] ?? null;
    if ($state !== null && isset($state["coordinates"])) {
        $coordinates = $state["coordinates"];
        $accuracy = $state["coordinates_accuracy_level"];
    }
    if ($city !== null && isset($city["coordinates"])) {
        $coordinates = $city["coordinates"];
        $accuracy = $city["coordinates_accuracy_level"];
    }

    $parts = [];
    if ($city !== null) $parts[] = $city["name"];
    if ($state !== null) $parts[] = $state["name"];
    $parts[] = $country["name"];

    return [
        "loccountry" => $country["name"],
        "locstate" => $state["name"] ?? null,
        "loccity" => $city["name"] ?? null,
        "coordinates" => $coordinates,
        "coordinates_accuracy_level" => $accuracy,
        "map_search_string" => implode(", ", $parts),
    ];
}

var_export(findLocation($countries, "PL"));
var_export(findLocation($countries, "PL", "86"));
var_export(findLocation($countries, "PL", "86", 35924));
```

## Java (Jackson `ObjectMapper`)

Jackson is the de facto standard JSON library in the Java ecosystem (and what Spring
uses by default).

```java
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.File;
import java.util.ArrayList;
import java.util.List;

public class Locations {
    record Location(String locCountry, String locState, String locCity,
                     String coordinates, String coordinatesAccuracyLevel,
                     String mapSearchString) {}

    static Location findLocation(JsonNode countries, String countryCode, String stateCode, Integer cityId) {
        JsonNode country = countries.get(countryCode);
        if (country == null) return null;

        JsonNode state = stateCode != null ? country.get("states").get(stateCode) : null;
        JsonNode city = (state != null && cityId != null) ? state.get("cities").get(String.valueOf(cityId)) : null;

        String coordinates = country.path("coordinates").asText(null);
        String accuracy = country.path("coordinates_accuracy_level").asText(null);
        if (state != null && state.hasNonNull("coordinates")) {
            coordinates = state.get("coordinates").asText();
            accuracy = state.get("coordinates_accuracy_level").asText();
        }
        if (city != null && city.hasNonNull("coordinates")) {
            coordinates = city.get("coordinates").asText();
            accuracy = city.get("coordinates_accuracy_level").asText();
        }

        List<String> parts = new ArrayList<>();
        if (city != null) parts.add(city.get("name").asText());
        if (state != null) parts.add(state.get("name").asText());
        parts.add(country.get("name").asText());

        return new Location(
                country.get("name").asText(),
                state != null ? state.get("name").asText() : null,
                city != null ? city.get("name").asText() : null,
                coordinates,
                accuracy,
                String.join(", ", parts)
        );
    }

    public static void main(String[] args) throws Exception {
        ObjectMapper mapper = new ObjectMapper();
        JsonNode countries = mapper.readTree(new File("data/steam_countries.json"));

        System.out.println("Case 1: " + findLocation(countries, "PL", null, null));
        System.out.println("Case 2: " + findLocation(countries, "PL", "86", null));
        System.out.println("Case 3: " + findLocation(countries, "PL", "86", 35924));
    }
}
```

Output (verified, `record`'s auto-generated `toString`):

```
Case 1: Location[locCountry=Poland, locState=null, locCity=null, coordinates=51.91943800000001,19.145136, coordinatesAccuracyLevel=country, mapSearchString=Poland]
Case 2: Location[locCountry=Poland, locState=Wielkopolskie, locCity=null, coordinates=52.279986,17.352294, coordinatesAccuracyLevel=state, mapSearchString=Wielkopolskie, Poland]
Case 3: Location[locCountry=Poland, locState=Wielkopolskie, locCity=Poznan, coordinates=52.406374,16.925168, coordinatesAccuracyLevel=city, mapSearchString=Poznan, Wielkopolskie, Poland]
```

## Kotlin (Gson)

```kotlin
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import java.io.File

data class Location(
    val locCountry: String,
    val locState: String?,
    val locCity: String?,
    val coordinates: String?,
    val coordinatesAccuracyLevel: String?,
    val mapSearchString: String
)

fun findLocation(
    countries: JsonObject,
    countryCode: String,
    stateCode: String? = null,
    cityId: Int? = null
): Location? {
    val country = countries.getAsJsonObject(countryCode) ?: return null

    val state = stateCode?.let { country.getAsJsonObject("states").getAsJsonObject(it) }
    val city = if (state != null && cityId != null)
        state.getAsJsonObject("cities").getAsJsonObject(cityId.toString()) else null

    var coordinates = country.get("coordinates")?.asString
    var accuracy = country.get("coordinates_accuracy_level")?.asString
    if (state?.get("coordinates") != null) {
        coordinates = state.get("coordinates").asString
        accuracy = state.get("coordinates_accuracy_level").asString
    }
    if (city?.get("coordinates") != null) {
        coordinates = city.get("coordinates").asString
        accuracy = city.get("coordinates_accuracy_level").asString
    }

    val parts = listOfNotNull(
        city?.get("name")?.asString,
        state?.get("name")?.asString,
        country.get("name").asString
    )

    return Location(
        country.get("name").asString,
        state?.get("name")?.asString,
        city?.get("name")?.asString,
        coordinates,
        accuracy,
        parts.joinToString(", ")
    )
}

fun main() {
    val countries = JsonParser.parseString(File("data/steam_countries.json").readText()).asJsonObject

    println("Case 1: ${findLocation(countries, "PL")}")
    println("Case 2: ${findLocation(countries, "PL", "86")}")
    println("Case 3: ${findLocation(countries, "PL", "86", 35924)}")
}
```

## C# (`System.Text.Json`, built-in)

```csharp
using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

class Program
{
    record Location(string LocCountry, string? LocState, string? LocCity,
                     string? Coordinates, string? CoordinatesAccuracyLevel, string MapSearchString);

    static Location? FindLocation(JsonElement countries, string countryCode,
                                   string? stateCode = null, int? cityId = null)
    {
        if (!countries.TryGetProperty(countryCode, out var country)) return null;

        JsonElement state = default;
        bool hasState = stateCode != null &&
            country.GetProperty("states").TryGetProperty(stateCode, out state);

        JsonElement city = default;
        bool hasCity = hasState && cityId != null &&
            state.GetProperty("cities").TryGetProperty(cityId.Value.ToString(), out city);

        string? coordinates = country.TryGetProperty("coordinates", out var cc) ? cc.GetString() : null;
        string? accuracy = country.TryGetProperty("coordinates_accuracy_level", out var ca) ? ca.GetString() : null;
        if (hasState && state.TryGetProperty("coordinates", out var sc))
        {
            coordinates = sc.GetString();
            accuracy = state.GetProperty("coordinates_accuracy_level").GetString();
        }
        if (hasCity && city.TryGetProperty("coordinates", out var cic))
        {
            coordinates = cic.GetString();
            accuracy = city.GetProperty("coordinates_accuracy_level").GetString();
        }

        var parts = new List<string>();
        if (hasCity) parts.Add(city.GetProperty("name").GetString()!);
        if (hasState) parts.Add(state.GetProperty("name").GetString()!);
        parts.Add(country.GetProperty("name").GetString()!);

        return new Location(
            country.GetProperty("name").GetString()!,
            hasState ? state.GetProperty("name").GetString() : null,
            hasCity ? city.GetProperty("name").GetString() : null,
            coordinates,
            accuracy,
            string.Join(", ", parts)
        );
    }

    static void Main()
    {
        var json = File.ReadAllText("data/steam_countries.json");
        using var doc = JsonDocument.Parse(json);
        var countries = doc.RootElement;

        Console.WriteLine($"Case 1: {FindLocation(countries, "PL")}");
        Console.WriteLine($"Case 2: {FindLocation(countries, "PL", "86")}");
        Console.WriteLine($"Case 3: {FindLocation(countries, "PL", "86", 35924)}");
    }
}
```

## Go (`encoding/json`, standard library)

```go
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"
)

type City struct {
	Name        string `json:"name"`
	Coordinates string `json:"coordinates"`
	Accuracy    string `json:"coordinates_accuracy_level"`
}

type State struct {
	Name        string          `json:"name"`
	Cities      map[string]City `json:"cities"`
	Coordinates string          `json:"coordinates"`
	Accuracy    string          `json:"coordinates_accuracy_level"`
}

type Country struct {
	Name        string           `json:"name"`
	States      map[string]State `json:"states"`
	Coordinates string           `json:"coordinates"`
	Accuracy    string           `json:"coordinates_accuracy_level"`
}

type Location struct {
	LocCountry               string
	LocState                 string
	LocCity                  string
	Coordinates              string
	CoordinatesAccuracyLevel string
	MapSearchString          string
}

func findLocation(countries map[string]Country, countryCode string, stateCode *string, cityID *int) *Location {
	country, ok := countries[countryCode]
	if !ok {
		return nil
	}

	var state *State
	if stateCode != nil {
		if s, ok := country.States[*stateCode]; ok {
			state = &s
		}
	}

	var city *City
	if state != nil && cityID != nil {
		if c, ok := state.Cities[strconv.Itoa(*cityID)]; ok {
			city = &c
		}
	}

	coordinates, accuracy := country.Coordinates, country.Accuracy
	if state != nil && state.Coordinates != "" {
		coordinates, accuracy = state.Coordinates, state.Accuracy
	}
	if city != nil && city.Coordinates != "" {
		coordinates, accuracy = city.Coordinates, city.Accuracy
	}

	parts := []string{}
	if city != nil {
		parts = append(parts, city.Name)
	}
	if state != nil {
		parts = append(parts, state.Name)
	}
	parts = append(parts, country.Name)

	loc := &Location{
		LocCountry:               country.Name,
		Coordinates:              coordinates,
		CoordinatesAccuracyLevel: accuracy,
		MapSearchString:          strings.Join(parts, ", "),
	}
	if state != nil {
		loc.LocState = state.Name
	}
	if city != nil {
		loc.LocCity = city.Name
	}
	return loc
}

func main() {
	data, err := os.ReadFile("data/steam_countries.json")
	if err != nil {
		panic(err)
	}

	var countries map[string]Country
	if err := json.Unmarshal(data, &countries); err != nil {
		panic(err)
	}

	state := "86"
	cityID := 35924

	fmt.Printf("Case 1: %+v\n", findLocation(countries, "PL", nil, nil))
	fmt.Printf("Case 2: %+v\n", findLocation(countries, "PL", &state, nil))
	fmt.Printf("Case 3: %+v\n", findLocation(countries, "PL", &state, &cityID))
}
```

Output (verified):

```
Case 1: &{LocCountry:Poland LocState: LocCity: Coordinates:51.91943800000001,19.145136 CoordinatesAccuracyLevel:country MapSearchString:Poland}
Case 2: &{LocCountry:Poland LocState:Wielkopolskie LocCity: Coordinates:52.279986,17.352294 CoordinatesAccuracyLevel:state MapSearchString:Wielkopolskie, Poland}
Case 3: &{LocCountry:Poland LocState:Wielkopolskie LocCity:Poznan Coordinates:52.406374,16.925168 CoordinatesAccuracyLevel:city MapSearchString:Poznan, Wielkopolskie, Poland}
```

## Rust (`serde_json`)

`serde_json` is the standard JSON crate in the Rust ecosystem. This uses its dynamic
`Value` type rather than deriving structs, since the file's shape (arbitrary country/
state/city codes as object keys) doesn't map cleanly onto fixed fields.

```rust
use serde_json::Value;
use std::fs;

#[derive(Debug)]
struct Location {
    loc_country: String,
    loc_state: Option<String>,
    loc_city: Option<String>,
    coordinates: Option<String>,
    coordinates_accuracy_level: Option<String>,
    map_search_string: String,
}

fn find_location(
    countries: &Value,
    country_code: &str,
    state_code: Option<&str>,
    city_id: Option<i64>,
) -> Option<Location> {
    let country = countries.get(country_code)?;

    let state = state_code.and_then(|sc| country["states"].get(sc));
    let city = state.and_then(|s| city_id.and_then(|id| s["cities"].get(id.to_string())));

    let mut coordinates = country["coordinates"].as_str().map(String::from);
    let mut accuracy = country["coordinates_accuracy_level"].as_str().map(String::from);
    if let Some(s) = state {
        if let Some(c) = s["coordinates"].as_str() {
            coordinates = Some(c.to_string());
            accuracy = s["coordinates_accuracy_level"].as_str().map(String::from);
        }
    }
    if let Some(c) = city {
        if let Some(coord) = c["coordinates"].as_str() {
            coordinates = Some(coord.to_string());
            accuracy = c["coordinates_accuracy_level"].as_str().map(String::from);
        }
    }

    let mut parts: Vec<&str> = Vec::new();
    if let Some(c) = city {
        parts.push(c["name"].as_str().unwrap());
    }
    if let Some(s) = state {
        parts.push(s["name"].as_str().unwrap());
    }
    parts.push(country["name"].as_str().unwrap());

    Some(Location {
        loc_country: country["name"].as_str().unwrap().to_string(),
        loc_state: state.map(|s| s["name"].as_str().unwrap().to_string()),
        loc_city: city.map(|c| c["name"].as_str().unwrap().to_string()),
        coordinates,
        coordinates_accuracy_level: accuracy,
        map_search_string: parts.join(", "),
    })
}

fn main() {
    let data = fs::read_to_string("data/steam_countries.json").unwrap();
    let countries: Value = serde_json::from_str(&data).unwrap();

    println!("Case 1: {:?}", find_location(&countries, "PL", None, None));
    println!("Case 2: {:?}", find_location(&countries, "PL", Some("86"), None));
    println!("Case 3: {:?}", find_location(&countries, "PL", Some("86"), Some(35924)));
}
```

Output (verified):

```
Case 1: Some(Location { loc_country: "Poland", loc_state: None, loc_city: None, coordinates: Some("51.91943800000001,19.145136"), coordinates_accuracy_level: Some("country"), map_search_string: "Poland" })
Case 2: Some(Location { loc_country: "Poland", loc_state: Some("Wielkopolskie"), loc_city: None, coordinates: Some("52.279986,17.352294"), coordinates_accuracy_level: Some("state"), map_search_string: "Wielkopolskie, Poland" })
Case 3: Some(Location { loc_country: "Poland", loc_state: Some("Wielkopolskie"), loc_city: Some("Poznan"), coordinates: Some("52.406374,16.925168"), coordinates_accuracy_level: Some("city"), map_search_string: "Poznan, Wielkopolskie, Poland" })
```

## Swift (`Foundation`, `JSONSerialization`)

```swift
import Foundation

let url = URL(fileURLWithPath: "data/steam_countries.json")
let data = try! Data(contentsOf: url)
let countries = try! JSONSerialization.jsonObject(with: data) as! [String: Any]

struct Location: CustomStringConvertible {
    let locCountry: String
    let locState: String?
    let locCity: String?
    let coordinates: String?
    let coordinatesAccuracyLevel: String?
    let mapSearchString: String

    var description: String {
        "locCountry=\(locCountry) locState=\(locState ?? "nil") locCity=\(locCity ?? "nil") " +
        "coordinates=\(coordinates ?? "nil") accuracy=\(coordinatesAccuracyLevel ?? "nil") " +
        "mapSearchString=\(mapSearchString)"
    }
}

func findLocation(countryCode: String, stateCode: String? = nil, cityId: Int? = nil) -> Location? {
    guard let country = countries[countryCode] as? [String: Any] else { return nil }
    let states = country["states"] as? [String: Any] ?? [:]

    let state = stateCode.flatMap { states[$0] as? [String: Any] }
    let cities = state?["cities"] as? [String: Any] ?? [:]
    let city = (state != nil && cityId != nil) ? cities[String(cityId!)] as? [String: Any] : nil

    var coordinates = country["coordinates"] as? String
    var accuracy = country["coordinates_accuracy_level"] as? String
    if let stateCoordinates = state?["coordinates"] as? String {
        coordinates = stateCoordinates
        accuracy = state?["coordinates_accuracy_level"] as? String
    }
    if let cityCoordinates = city?["coordinates"] as? String {
        coordinates = cityCoordinates
        accuracy = city?["coordinates_accuracy_level"] as? String
    }

    var parts: [String] = []
    if let cityName = city?["name"] as? String { parts.append(cityName) }
    if let stateName = state?["name"] as? String { parts.append(stateName) }
    parts.append(country["name"] as! String)

    return Location(
        locCountry: country["name"] as! String,
        locState: state?["name"] as? String,
        locCity: city?["name"] as? String,
        coordinates: coordinates,
        coordinatesAccuracyLevel: accuracy,
        mapSearchString: parts.joined(separator: ", ")
    )
}

print("Case 1:", findLocation(countryCode: "PL") ?? "not found")
print("Case 2:", findLocation(countryCode: "PL", stateCode: "86") ?? "not found")
print("Case 3:", findLocation(countryCode: "PL", stateCode: "86", cityId: 35924) ?? "not found")
```

## Dart (`dart:convert`, built-in)

```dart
import 'dart:convert';
import 'dart:io';

class Location {
  final String locCountry;
  final String? locState;
  final String? locCity;
  final String? coordinates;
  final String? coordinatesAccuracyLevel;
  final String mapSearchString;

  Location(this.locCountry, this.locState, this.locCity, this.coordinates,
      this.coordinatesAccuracyLevel, this.mapSearchString);

  @override
  String toString() =>
      'locCountry=$locCountry locState=$locState locCity=$locCity '
      'coordinates=$coordinates accuracy=$coordinatesAccuracyLevel '
      'mapSearchString=$mapSearchString';
}

Location? findLocation(Map<String, dynamic> countries, String countryCode,
    [String? stateCode, int? cityId]) {
  final country = countries[countryCode] as Map<String, dynamic>?;
  if (country == null) return null;

  final states = country['states'] as Map<String, dynamic>;
  final state = stateCode != null ? states[stateCode] as Map<String, dynamic>? : null;

  Map<String, dynamic>? city;
  if (state != null && cityId != null) {
    final cities = state['cities'] as Map<String, dynamic>;
    city = cities[cityId.toString()] as Map<String, dynamic>?;
  }

  var coordinates = country['coordinates'] as String?;
  var accuracy = country['coordinates_accuracy_level'] as String?;
  if (state?['coordinates'] != null) {
    coordinates = state!['coordinates'] as String;
    accuracy = state['coordinates_accuracy_level'] as String;
  }
  if (city?['coordinates'] != null) {
    coordinates = city!['coordinates'] as String;
    accuracy = city['coordinates_accuracy_level'] as String;
  }

  final parts = <String>[
    if (city != null) city['name'] as String,
    if (state != null) state['name'] as String,
    country['name'] as String,
  ];

  return Location(
    country['name'] as String,
    state?['name'] as String?,
    city?['name'] as String?,
    coordinates,
    accuracy,
    parts.join(', '),
  );
}

void main() {
  final countries =
      jsonDecode(File('data/steam_countries.json').readAsStringSync()) as Map<String, dynamic>;

  print('Case 1: ${findLocation(countries, 'PL')}');
  print('Case 2: ${findLocation(countries, 'PL', '86')}');
  print('Case 3: ${findLocation(countries, 'PL', '86', 35924)}');
}
```

## C++ (`nlohmann/json`)

`nlohmann/json` (`nlohmann-json3-dev` on Debian/Ubuntu) is the most widely used JSON
library in modern C++, and the one most C++ style guides point to by name.

```cpp
#include <fstream>
#include <iostream>
#include <optional>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

struct Location {
    std::string loc_country;
    std::optional<std::string> loc_state;
    std::optional<std::string> loc_city;
    std::optional<std::string> coordinates;
    std::optional<std::string> coordinates_accuracy_level;
    std::string map_search_string;
};

std::optional<Location> findLocation(const json &countries, const std::string &countryCode,
                                      std::optional<std::string> stateCode = std::nullopt,
                                      std::optional<long> cityId = std::nullopt) {
    if (!countries.contains(countryCode)) return std::nullopt;
    const json &country = countries[countryCode];

    const json *state = nullptr;
    if (stateCode && country["states"].contains(*stateCode)) {
        state = &country["states"][*stateCode];
    }

    const json *city = nullptr;
    if (state && cityId && (*state)["cities"].contains(std::to_string(*cityId))) {
        city = &(*state)["cities"][std::to_string(*cityId)];
    }

    std::optional<std::string> coordinates, accuracy;
    if (country.contains("coordinates")) coordinates = country["coordinates"];
    if (country.contains("coordinates_accuracy_level")) accuracy = country["coordinates_accuracy_level"];
    if (state && state->contains("coordinates")) {
        coordinates = (*state)["coordinates"];
        accuracy = (*state)["coordinates_accuracy_level"];
    }
    if (city && city->contains("coordinates")) {
        coordinates = (*city)["coordinates"];
        accuracy = (*city)["coordinates_accuracy_level"];
    }

    std::string mapSearchString;
    if (city) mapSearchString += city->at("name").get<std::string>() + ", ";
    if (state) mapSearchString += state->at("name").get<std::string>() + ", ";
    mapSearchString += country.at("name").get<std::string>();

    return Location{
        country["name"],
        state ? std::optional(state->at("name").get<std::string>()) : std::nullopt,
        city ? std::optional(city->at("name").get<std::string>()) : std::nullopt,
        coordinates,
        accuracy,
        mapSearchString,
    };
}

void print(const std::optional<Location> &loc) {
    if (!loc) { std::cout << "not found\n"; return; }
    std::cout << "loccountry=" << loc->loc_country
              << " locstate=" << loc->loc_state.value_or("(none)")
              << " loccity=" << loc->loc_city.value_or("(none)")
              << " coordinates=" << loc->coordinates.value_or("(none)")
              << " accuracy=" << loc->coordinates_accuracy_level.value_or("(none)")
              << " map_search_string=" << loc->map_search_string << "\n";
}

int main() {
    std::ifstream f("data/steam_countries.json");
    json countries = json::parse(f);

    std::cout << "Case 1: "; print(findLocation(countries, "PL"));
    std::cout << "Case 2: "; print(findLocation(countries, "PL", "86"));
    std::cout << "Case 3: "; print(findLocation(countries, "PL", "86", 35924));
}
```

Compile with `g++ -std=c++17 example.cpp -o example`. Output (verified):

```
Case 1: loccountry=Poland locstate=(none) loccity=(none) coordinates=51.91943800000001,19.145136 accuracy=country map_search_string=Poland
Case 2: loccountry=Poland locstate=Wielkopolskie loccity=(none) coordinates=52.279986,17.352294 accuracy=state map_search_string=Wielkopolskie, Poland
Case 3: loccountry=Poland locstate=Wielkopolskie loccity=Poznan coordinates=52.406374,16.925168 accuracy=city map_search_string=Poznan, Wielkopolskie, Poland
```

## Perl (`JSON::PP`, core since 5.14)

Read the file as raw bytes, not through a `:encoding(UTF-8)` layer — `decode_json`
expects UTF-8-encoded bytes and does the decoding itself; feeding it an
already-decoded string throws `Wide character in subroutine entry`.

```perl
use strict;
use warnings;
use JSON::PP;
use Data::Dumper;

open(my $fh, "<:raw", "data/steam_countries.json") or die $!;
local $/;
my $countries = decode_json(<$fh>);

sub find_location {
    my ($country_code, $state_code, $city_id) = @_;
    my $country = $countries->{$country_code} or return undef;

    my $state = defined $state_code ? $country->{states}{$state_code} : undef;
    my $city = ($state && defined $city_id) ? $state->{cities}{$city_id} : undef;

    my $coordinates = $country->{coordinates};
    my $accuracy    = $country->{coordinates_accuracy_level};
    if ($state && $state->{coordinates}) {
        $coordinates = $state->{coordinates};
        $accuracy    = $state->{coordinates_accuracy_level};
    }
    if ($city && $city->{coordinates}) {
        $coordinates = $city->{coordinates};
        $accuracy    = $city->{coordinates_accuracy_level};
    }

    my @parts;
    push @parts, $city->{name}  if $city;
    push @parts, $state->{name} if $state;
    push @parts, $country->{name};

    return {
        loccountry                 => $country->{name},
        locstate                   => $state ? $state->{name} : undef,
        loccity                    => $city  ? $city->{name}  : undef,
        coordinates                => $coordinates,
        coordinates_accuracy_level => $accuracy,
        map_search_string          => join(", ", @parts),
    };
}

print Dumper(find_location("PL"));
print Dumper(find_location("PL", "86"));
print Dumper(find_location("PL", "86", 35924));
```

Output (verified, values confirmed identical to every other example above):

```
$VAR1 = {'coordinates' => '51.91943800000001,19.145136','coordinates_accuracy_level' => 'country','loccity' => undef,'loccountry' => 'Poland','locstate' => undef,'map_search_string' => 'Poland'};
$VAR1 = {'coordinates' => '52.279986,17.352294','coordinates_accuracy_level' => 'state','loccity' => undef,'loccountry' => 'Poland','locstate' => 'Wielkopolskie','map_search_string' => 'Wielkopolskie, Poland'};
$VAR1 = {'coordinates' => '52.406374,16.925168','coordinates_accuracy_level' => 'city','loccity' => 'Poznan','loccountry' => 'Poland','locstate' => 'Wielkopolskie','map_search_string' => 'Poznan, Wielkopolskie, Poland'};
```

## R (`jsonlite`)

`simplifyVector = FALSE` matters here — without it, `jsonlite` tries to flatten nested
objects into data frames, which breaks the `$states[[code]]` style lookups below.

```r
library(jsonlite)

countries <- fromJSON("data/steam_countries.json", simplifyVector = FALSE)

find_location <- function(country_code, state_code = NULL, city_id = NULL) {
  country <- countries[[country_code]]
  if (is.null(country)) return(NULL)

  state <- if (!is.null(state_code)) country$states[[as.character(state_code)]] else NULL
  city <- if (!is.null(state) && !is.null(city_id)) state$cities[[as.character(city_id)]] else NULL

  coordinates <- country$coordinates
  accuracy <- country$coordinates_accuracy_level
  if (!is.null(state) && !is.null(state$coordinates)) {
    coordinates <- state$coordinates
    accuracy <- state$coordinates_accuracy_level
  }
  if (!is.null(city) && !is.null(city$coordinates)) {
    coordinates <- city$coordinates
    accuracy <- city$coordinates_accuracy_level
  }

  parts <- c(city$name, state$name, country$name)

  list(
    loccountry = country$name,
    locstate = state$name,
    loccity = city$name,
    coordinates = coordinates,
    coordinates_accuracy_level = accuracy,
    map_search_string = paste(parts, collapse = ", ")
  )
}

print(find_location("PL"))
print(find_location("PL", "86"))
print(find_location("PL", "86", 35924))
```

## PowerShell (`ConvertFrom-Json`, built-in)

`-AsHashtable` (PowerShell 6+) turns each JSON object into a `Hashtable` instead of a
`PSCustomObject`, so keys that happen to be dynamic country/state/city codes can be
indexed with `[...]` instead of fighting `PSCustomObject`'s property syntax.

```powershell
$countries = Get-Content "data/steam_countries.json" -Raw | ConvertFrom-Json -AsHashtable

function Find-Location {
    param(
        [string]$CountryCode,
        [string]$StateCode = $null,
        [Nullable[int]]$CityId = $null
    )

    $country = $countries[$CountryCode]
    if (-not $country) { return $null }

    $state = if ($null -ne $StateCode) { $country.states[$StateCode] } else { $null }
    $city = if ($state -and ($null -ne $CityId)) { $state.cities[[string]$CityId] } else { $null }

    $coordinates = $country.coordinates
    $accuracy = $country.coordinates_accuracy_level
    if ($state -and $state.coordinates) {
        $coordinates = $state.coordinates
        $accuracy = $state.coordinates_accuracy_level
    }
    if ($city -and $city.coordinates) {
        $coordinates = $city.coordinates
        $accuracy = $city.coordinates_accuracy_level
    }

    $parts = @($city.name, $state.name, $country.name) | Where-Object { $_ }

    [PSCustomObject]@{
        loccountry                 = $country.name
        locstate                   = $state.name
        loccity                    = $city.name
        coordinates                = $coordinates
        coordinates_accuracy_level = $accuracy
        map_search_string          = ($parts -join ", ")
    }
}

Find-Location -CountryCode "PL"
Find-Location -CountryCode "PL" -StateCode "86"
Find-Location -CountryCode "PL" -StateCode "86" -CityId 35924
```

## Bonus: `jq` (command line, no host language)

Since the file is meant to be usable without any library at all, here's the same three
cases as one-liners with [`jq`](https://jqlang.org/):

```bash
# Case 1: country only
jq '.PL | {loccountry: .name, coordinates, coordinates_accuracy_level, map_search_string: .name}' \
  data/steam_countries.json

# Case 2: country + state
jq '.PL as $c | $c.states["86"] as $s | {
      loccountry: $c.name, locstate: $s.name,
      coordinates: ($s.coordinates // $c.coordinates),
      coordinates_accuracy_level: ($s.coordinates_accuracy_level // $c.coordinates_accuracy_level),
      map_search_string: ($s.name + ", " + $c.name)
    }' data/steam_countries.json

# Case 3: country + state + city
jq '.PL as $c | $c.states["86"] as $s | $s.cities["35924"] as $city | {
      loccountry: $c.name, locstate: $s.name, loccity: $city.name,
      coordinates: ($city.coordinates // $s.coordinates // $c.coordinates),
      coordinates_accuracy_level: ($city.coordinates_accuracy_level // $s.coordinates_accuracy_level // $c.coordinates_accuracy_level),
      map_search_string: ($city.name + ", " + $s.name + ", " + $c.name)
    }' data/steam_countries.json
```

The `//` operator is jq's "use the left side unless it's `null`", which is exactly the
country → state → city fallback used everywhere else in this document. Output
(verified) for case 3:

```json
{
  "loccountry": "Poland",
  "locstate": "Wielkopolskie",
  "loccity": "Poznan",
  "coordinates": "52.406374,16.925168",
  "coordinates_accuracy_level": "city",
  "map_search_string": "Poznan, Wielkopolskie, Poland"
}
```
