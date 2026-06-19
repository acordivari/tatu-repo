

require 'scrapifier'

'Wow! What an awesome site: http://www.maccosmetics.com/product/13854/310/products/makeup/lips/lipstick/lipstick'.scrapify(images: :jpg)

str = 'Wow! What an awesome site: http://www.maccosmetics.com/product/13854/310/products/makeup/lips/lipstick/lipstick'
puts str.scrapify
