require "insta_scrape"

scrape_result = InstaScrape.long_scrape_user_info_and_posts("blackworkers", 12)

scrape_result.each do |post|
puts post
puts post.link
end

puts scrape_result.length
