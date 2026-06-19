require "csv"
require "insta_scrape"

def appendRowToCsv(row)
  CSV.open("insta_posts_final.csv", "a+",) do |csv|
    csv << row
  end
end

# create headers
appendRowToCsv(['image', 'link']);

# iterate through posts appending each new photo to csv
scrape_result = InstaScrape.long_scrape_user_info_and_posts("blackworkers", 15) #change the scrape method / tag to what you want
scrape_result.posts.each do |post|
  appendRowToCsv([post.image, post.link])
end
