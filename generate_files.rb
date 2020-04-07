# generate_jsons

require "csv"
require "json"
require 'uri'
require 'open-uri'
require "rss"
require "date"
require "yaml"

cache    = "./cache"
rss_dir  = "./public/rss"
csv_file = "./album_of_the_day.csv"
config   = "./config.yml"

# https://api.song.link/v1-alpha.1/links?url=spotify%3Aalbum%3A5OZHQ7KG8k04IOkF50fACO&userCountry=FR
songlink_api = "https://api.song.link/v1-alpha.1/links"

config = {
  "userCountry" => "FR"
}

base_url = songlink_api + "?"

config.each { |k,v| base_url+="#{URI::encode(k)}=#{URI::encode(v)}&" } 

all_days = {}

CSV.read(csv_file, :headers => true).each do |row|
  row = row.to_h
  file_name = "#{cache}/#{row['date']}.json"
  data = {}
  if File.exist?(file_name)
    data = JSON.parse(File.open(file_name).read)
  else
    url = base_url + "url=#{row['spotify-app']}"
    # puts url
    open(url) do |f|
      data = JSON.parse(f.read)
      File.open(file_name, "w") {|file| file << JSON.pretty_generate(data) }      
    end
  end
  ## thumbnail
  row["thumbnail"] = data["entitiesByUniqueId"][data["entityUniqueId"]]["thumbnailUrl"]

  ## find links
  row["providers"] = {}
  data["linksByPlatform"].each do |k,v| 
      row["providers"][k]=v["url"]
  end
  all_days[row["date"]] = row
end

rss_generators = {}

def rss_generator(provider, data)
  rss = RSS::Maker.make("atom") do |maker|
    maker.channel.author = "mortenjohs"
    maker.channel.updated = Time.now.to_s
    maker.channel.about = "https://ervik.hopto.org/aotd/rss/#{provider}.xml"
    maker.channel.title = "Album of the day on #{provider}"
    data.each do |date, album| 
      if Date.today >= Date.strptime(date)
        unless album["providers"][provider].nil?
          maker.items.new_item do |item|
            item.link = album["providers"][provider]
            item.title = "#{date}: #{album['artist']} -- #{album['album']}"
            item.updated = date
            item.description = "#{album['comment']}"
          end
        end
      end
    end
  end
  rss
end

providers = []
all_days.each {|date, album| providers<<album["providers"].keys;providers = providers.flatten.uniq }

puts providers

providers.each do |p| 
  File.open("#{rss_dir}/#{p}.xml", "w") do |f|
    f << rss_generator(p, all_days)
  end
end

